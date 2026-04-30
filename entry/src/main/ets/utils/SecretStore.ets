/*
 * SecretStore.ets
 *
 * 基于 HUKS（Universal Keystore Kit）的 AES-256-GCM 凭证加解密。
 *
 * 设计要点：
 *   1. master key 由 HUKS 生成，不可导出（绑定 TEE / SE），应用只持 keyAlias 句柄。
 *      即使 root 设备 dump 应用沙箱，也无法直接解密本地 cipher。
 *   2. 加解密走 HUKS 三段式：initSession → finishSession（GCM 小数据无需 update）。
 *   3. 输出 base64 包装：[12B nonce] [N cipher] [16B authTag]，便于直接当字符串持久化。
 *   4. 任何阶段失败都不抛错，回退原文（向后兼容旧明文凭证 & 容忍偶发 HUKS 异常）。
 *
 * 用法：
 *   await SecretStore.init();                      // EntryAbility.onCreate 中调用一次
 *   const c: string = await SecretStore.encrypt(s); // 加密
 *   const p: string = await SecretStore.decrypt(c); // 解密；非密文输入原样返回
 */

import { huks } from '@kit.UniversalKeystoreKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from './Logger';

const TAG: string = 'SecretStore';

/** master key 的 HUKS 别名。版本号变更时旧凭证会无法解密 → 走 fallback。 */
const KEY_ALIAS: string = 'hlib_credential_master_v1';

/** AES-GCM 推荐 nonce 长度（位 96 = 12 字节）。 */
const NONCE_LEN: number = 12;
/** AES-GCM authTag 固定 16 字节。 */
const TAG_LEN: number = 16;

/** 自定义前缀：写盘 cipher 必带，读时据此判断是 cipher 还是旧明文。 */
const CIPHER_PREFIX: string = 'sec1:';

const TEXT_ENCODER: util.TextEncoder = new util.TextEncoder('utf-8');
const TEXT_DECODER: util.TextDecoder = util.TextDecoder.create('utf-8');
const BASE64: util.Base64Helper = new util.Base64Helper();

/** HUKS GCM 通用 properties 工厂——避免散落在多个方法中容易写错。 */
function makeGcmProps(purpose: number, nonce?: Uint8Array, authTag?: Uint8Array): Array<huks.HuksParam> {
  const props: Array<huks.HuksParam> = [
    { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
    { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
    { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: purpose },
    { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
    { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
    { tag: huks.HuksTag.HUKS_TAG_DIGEST, value: huks.HuksKeyDigest.HUKS_DIGEST_NONE },
  ];
  if (nonce !== undefined) {
    props.push({ tag: huks.HuksTag.HUKS_TAG_NONCE, value: nonce });
  }
  if (authTag !== undefined) {
    props.push({ tag: huks.HuksTag.HUKS_TAG_AE_TAG, value: authTag });
  }
  return props;
}

export class SecretStore {
  private static initialized: boolean = false;
  /** init 失败时降级到 false，所有 encrypt/decrypt 都直通明文。 */
  private static usable: boolean = false;

  /** 读取 / 生成 master key。EntryAbility.onCreate 必须最早调一次。 */
  static async init(): Promise<void> {
    if (SecretStore.initialized) {
      return;
    }
    SecretStore.initialized = true;

    try {
      const exists: boolean = await SecretStore.hasKey();
      if (!exists) {
        await SecretStore.generateKey();
        Logger.i(TAG, 'master key generated in HUKS');
      } else {
        Logger.i(TAG, 'master key reused');
      }
      SecretStore.usable = true;
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      Logger.w(TAG, `init failed (fallback to plaintext): code=${e.code} msg=${e.message}`);
      SecretStore.usable = false;
    }
  }

  static isUsable(): boolean {
    return SecretStore.usable;
  }

  // ─── 加解密 ───────────────────────────────────────────

  /** 加密：plain → "sec1:<base64(nonce|cipher|tag)>"；失败回退原文。 */
  static async encrypt(plain: string): Promise<string> {
    if (!SecretStore.usable || plain.length === 0) {
      return plain;
    }
    if (plain.startsWith(CIPHER_PREFIX)) {
      return plain;
    }

    try {
      const data: Uint8Array = TEXT_ENCODER.encodeInto(plain);
      const nonce: Uint8Array = await SecretStore.randomBytes(NONCE_LEN);

      const opts: huks.HuksOptions = {
        properties: makeGcmProps(huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT, nonce),
        inData: data,
      };
      const session: huks.HuksSessionHandle = await huks.initSession(KEY_ALIAS, opts);
      const finishOut: huks.HuksReturnResult = await huks.finishSession(session.handle, opts);

      const out: Uint8Array | undefined = finishOut.outData;
      if (out === undefined || out.length < TAG_LEN) {
        return plain;
      }

      // 输出包：[12B nonce][N cipher][16B tag] —— HUKS GCM 加密时 outData = cipher||tag
      const composed: Uint8Array = new Uint8Array(NONCE_LEN + out.length);
      composed.set(nonce, 0);
      composed.set(out, NONCE_LEN);

      const b64: string = BASE64.encodeToStringSync(composed);
      return `${CIPHER_PREFIX}${b64}`;
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      Logger.w(TAG, `encrypt failed: code=${e.code} msg=${e.message}`);
      return plain;
    }
  }

  /** 解密：cipher 必须以 "sec1:" 开头，否则视为旧明文原样返回。 */
  static async decrypt(input: string): Promise<string> {
    if (input.length === 0 || !input.startsWith(CIPHER_PREFIX)) {
      return input;
    }
    if (!SecretStore.usable) {
      // master key 不可用：旧 cipher 没办法解，回退空（避免把 sec1:xxx 直接当用户名）
      Logger.w(TAG, 'decrypt skipped: HUKS not usable');
      return '';
    }

    try {
      const b64: string = input.substring(CIPHER_PREFIX.length);
      const composed: Uint8Array = BASE64.decodeSync(b64);
      if (composed.length < NONCE_LEN + TAG_LEN) {
        return '';
      }

      const nonce: Uint8Array = composed.slice(0, NONCE_LEN);
      const cipherWithTag: Uint8Array = composed.slice(NONCE_LEN);
      const tagStart: number = cipherWithTag.length - TAG_LEN;
      const cipher: Uint8Array = cipherWithTag.slice(0, tagStart);
      const authTag: Uint8Array = cipherWithTag.slice(tagStart);

      const opts: huks.HuksOptions = {
        properties: makeGcmProps(huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT, nonce, authTag),
        inData: cipher,
      };
      const session: huks.HuksSessionHandle = await huks.initSession(KEY_ALIAS, opts);
      const finishOut: huks.HuksReturnResult = await huks.finishSession(session.handle, opts);

      const out: Uint8Array | undefined = finishOut.outData;
      if (out === undefined) {
        return '';
      }
      return TEXT_DECODER.decodeToString(out);
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      Logger.w(TAG, `decrypt failed: code=${e.code} msg=${e.message}`);
      return '';
    }
  }

  // ─── 内部 ───────────────────────────────────────────

  private static async hasKey(): Promise<boolean> {
    try {
      const opts: huks.HuksOptions = { properties: [] };
      return await huks.hasKeyItem(KEY_ALIAS, opts);
    } catch {
      return false;
    }
  }

  private static async generateKey(): Promise<void> {
    const props: Array<huks.HuksParam> = [
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
      { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
      {
        tag: huks.HuksTag.HUKS_TAG_PURPOSE,
        value:
          huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT |
          huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT,
      },
      { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
      { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
      { tag: huks.HuksTag.HUKS_TAG_DIGEST, value: huks.HuksKeyDigest.HUKS_DIGEST_NONE },
    ];
    const opts: huks.HuksOptions = { properties: props };
    try {
      await huks.generateKeyItem(KEY_ALIAS, opts);
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      throw new Error(`huks.generateKeyItem failed: code=${e.code} msg=${e.message}`);
    }
  }

  /** 取强随机字节（GCM nonce）。HUKS 自身没暴露 random，借 cryptoFramework 的。 */
  private static async randomBytes(len: number): Promise<Uint8Array> {
    try {
      const rand: cryptoFramework.Random = cryptoFramework.createRandom();
      const blob: cryptoFramework.DataBlob = await rand.generateRandom(len);
      return blob.data;
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      throw new Error(`cryptoFramework random failed: code=${e.code} msg=${e.message}`);
    }
  }
}
