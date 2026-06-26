import localUnitTest from './LocalUnit.test';
import pureUtilsTest from './PureUtils.test';

export default function testsuite() {
  localUnitTest();
  pureUtilsTest();
}
