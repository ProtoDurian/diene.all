import type { Result } from '@atomicloud/diene.result';
import 'should';
import { expectErr, expectOk } from '../support/capture.js';

interface SequenceDriver {
  readonly label: string;
  record(): Promise<void> | void;
  sequences(): readonly number[];
}

async function runSequenceContract(driver: SequenceDriver): Promise<void> {
  await driver.record();
  await driver.record();
  await driver.record();
  driver.sequences().should.eql([0, 1, 2]);
}

interface FailInjectionDriver<E> {
  readonly label: string;
  makeError(): E;
  injectFailure(error: E): void;
  callFallible(): Result<unknown, E>;
}

async function runFailInjectionContract<E>(driver: FailInjectionDriver<E>): Promise<void> {
  const error = driver.makeError();
  driver.injectFailure(error);
  const failed = await expectErr(driver.callFallible());
  (failed === error).should.be.true();
  await expectOk(driver.callFallible());
}

interface SnapshotDriver {
  readonly label: string;
  produce(): Promise<void> | void;
  readSnapshot(): readonly unknown[];
}

async function runSnapshotIsolationContract(driver: SnapshotDriver): Promise<void> {
  await driver.produce();
  const first = driver.readSnapshot();
  const second = driver.readSnapshot();
  (first === second).should.be.false();
  first.should.eql(second);
  first.length.should.be.aboveOrEqual(1);
  // Entries are frozen; the array wrapper need not be.
  Object.isFrozen(first[0]).should.be.true();
}

export { runFailInjectionContract, runSequenceContract, runSnapshotIsolationContract };
