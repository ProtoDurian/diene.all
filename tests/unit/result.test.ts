import { describe, it } from 'bun:test';
import 'should';
import { UnwrapError } from '../../src/lib/error.js';
import { Err, KResult, Ok, Res, type Result } from '../../src/lib/result.js';

describe('Result construction and serialization', () => {
  it('should construct Ok and Err values from immediate and promised payloads', async () => {
    // Arrange
    const promisedValue = Promise.resolve(7);
    const promisedError = Promise.resolve('boom');

    // Act
    const ok = Ok<number, string>(promisedValue);
    const err = Err<number, string>(promisedError);

    // Assert
    ok.should.be.instanceof(KResult);
    (await ok.isOk()).should.be.true();
    (await ok.isErr()).should.be.false();
    (await ok.unwrap()).should.equal(7);
    (await err.isErr()).should.be.true();
    (await err.isOk()).should.be.false();
    (await err.unwrapErr()).should.equal('boom');
  });

  it('should round-trip both ResultSerial variants through JSON', async () => {
    // Arrange
    const okWire = JSON.parse(JSON.stringify(await Ok<number, string>(11).serial())) as ['ok', number];
    const errWire = JSON.parse(JSON.stringify(await Err<number, string>('bad').serial())) as ['err', string];

    // Act
    const ok = Res.fromSerial<number, string>(Promise.resolve(okWire));
    const err = Res.fromSerial<number, string>(errWire);

    // Assert
    (await ok.unwrap()).should.equal(11);
    (await err.unwrapErr()).should.equal('bad');
  });

  it('should flatten promised Results through fromAsync and async', async () => {
    // Arrange
    const promisedOk = Promise.resolve(Ok<number, string>(3));
    const promisedErr = Promise.resolve(Err<number, string>('no'));

    // Act
    const ok = Res.fromAsync(promisedOk);
    const err = Res.fromAsync(promisedErr);
    const asyncResult = Res.async(async () => Ok<number, string>(9));

    // Assert
    (await ok.unwrap()).should.equal(3);
    (await err.unwrapErr()).should.equal('no');
    (await asyncResult.unwrap()).should.equal(9);
  });

  it('should collect all Ok payloads and collect every Err payload', async () => {
    // Arrange
    const allOk = [Ok<number, string>(1), Ok<string, string>('two')] as const;
    const mixed = [Ok<number, string>(1), Err<string, string>('first'), Err<boolean, string>('second')] as const;

    // Act
    const okResult = Res.all(...allOk);
    const errResult = Res.all(...mixed);

    // Assert
    (await okResult.unwrap()).should.deepEqual([1, 'two']);
    (await errResult.unwrapErr()).should.deepEqual(['first', 'second']);
  });
});

describe('Result transforms', () => {
  it('should map only Ok and mapErr only Err with async-aware mappers', async () => {
    // Arrange
    const ok = Ok<number, string>(2);
    const err = Err<number, string>('bad');

    // Act
    const mappedOk = ok.map(async value => value * 10);
    const untouchedErr = err.map(value => value * 10);
    const untouchedOk = ok.mapErr(error => `${error}!`);
    const mappedErr = err.mapErr(async error => `${error}!`);

    // Assert
    (await mappedOk.unwrap()).should.equal(20);
    (await untouchedErr.unwrapErr()).should.equal('bad');
    (await untouchedOk.unwrap()).should.equal(2);
    (await mappedErr.unwrapErr()).should.equal('bad!');
  });

  it('should chain Ok values and short-circuit Err values', async () => {
    // Arrange
    const ok = Ok<number, string>(4);
    const err = Err<number, string>('stop');

    // Act
    const chainedOk = ok.andThen(async value => Ok<string, string>(`v:${value}`));
    const chainedToErr = ok.andThen(value => Err<string, string>(`e:${value}`));
    const chainedErr = err.andThen(value => Ok<string, string>(`v:${value}`));

    // Assert
    (await chainedOk.unwrap()).should.equal('v:4');
    (await chainedToErr.unwrapErr()).should.equal('e:4');
    (await chainedErr.unwrapErr()).should.equal('stop');
  });

  it('should match both variants and expose their native payloads', async () => {
    // Arrange
    const ok = Ok<number, string>(5);
    const err = Err<number, string>('x');
    const arms = { ok: async (value: number) => `ok:${value}`, err: async (error: string) => `err:${error}` };

    // Act
    const okMatch = ok.match(arms);
    const errMatch = err.match(arms);

    // Assert
    (await okMatch).should.equal('ok:5');
    (await errMatch).should.equal('err:x');
    (await ok.native()).should.equal(5);
    (await err.native()).should.equal('x');
  });
});

describe('Result extraction and projection', () => {
  it('should throw UnwrapError only for explicit wrong-variant unwraps', async () => {
    // Arrange
    const ok = Ok<number, string>(8);
    const err = Err<number, string>('why');

    // Act
    const unwrapErrFromOk = (await ok.unwrapErr().catch(error => error as UnwrapError)) as UnwrapError;
    const unwrapOkFromErr = (await err.unwrap().catch(error => error as UnwrapError)) as UnwrapError;

    // Assert
    unwrapErrFromOk.should.be.instanceof(UnwrapError);
    unwrapErrFromOk.type.should.equal('Expected Err got Ok');
    unwrapErrFromOk.monadType.should.equal('result');
    unwrapOkFromErr.should.be.instanceof(UnwrapError);
    unwrapOkFromErr.type.should.equal('Expected Ok got Error');
    unwrapOkFromErr.monadType.should.equal('result');
  });

  it('should return immediate, promised, sync-deferred, and async-deferred fallbacks', async () => {
    // Arrange
    const ok = Ok<number, string>(1);
    const err = Err<number, string>('four');

    // Act / Assert
    (await ok.unwrapOr(99)).should.equal(1);
    (await err.unwrapOr(99)).should.equal(99);
    (await err.unwrapOr(Promise.resolve(88))).should.equal(88);
    (await err.unwrapOr(error => error.length)).should.equal(4);
    (await err.unwrapOr(async error => error.length + 1)).should.equal(5);
  });

  it('should project each channel into Option', async () => {
    // Arrange
    const ok = Ok<number, string>(2);
    const err = Err<number, string>('z');

    // Act
    const okSome = ok.ok();
    const okNone = err.ok();
    const errNone = ok.err();
    const errSome = err.err();

    // Assert
    (await okSome.unwrap()).should.equal(2);
    (await okNone.isNone()).should.be.true();
    (await errNone.isNone()).should.be.true();
    (await errSome.unwrap()).should.equal('z');
  });
});

describe('Result side effects', () => {
  it('should run sync and async effects only for Ok while preserving the Result', async () => {
    // Arrange
    const seen: number[] = [];
    const ok = Ok<number, string>(6);
    const err = Err<number, string>('skip');

    // Act
    const afterSync = ok.run(value => {
      seen.push(value);
    });
    const afterAsync = afterSync.run(async value => {
      seen.push(value + 1);
    });
    const afterErr = err.run(value => {
      seen.push(value);
    });

    // Assert
    (await afterAsync.unwrap()).should.equal(6);
    (await afterErr.unwrapErr()).should.equal('skip');
    seen.should.deepEqual([6, 7]);
  });

  it('should preserve successful exec values and normalize every thrown shape', async () => {
    // Arrange
    const ok = Ok<number, string>(7);

    // Act
    const success = ok.exec(async () => undefined);
    const fromError = ok.exec(() => {
      throw new Error('error-shape');
    });
    const fromString = ok.exec(() => {
      throw 'string-shape';
    });
    const fromObject = ok.exec(() => {
      throw { shape: 'object' };
    });

    // Assert
    (await success.unwrap()).should.equal(7);
    (await fromError.unwrapErr()).message.should.equal('error-shape');
    (await fromString.unwrapErr()).message.should.equal('string-shape');
    (await fromObject.unwrapErr()).message.should.equal('{"shape":"object"}');
  });

  it('should map pre-existing Err values through the default and custom exec mappers', async () => {
    // Arrange
    const nativeError = new Error('native');
    const errorErr = Err<number, Error>(nativeError);
    const objectErr = Err<number, { code: number }>({ code: 4 });
    const stringErr = Err<number, string>('raw');

    // Act
    const preserved = errorErr.exec(() => undefined);
    const normalized = objectErr.exec(() => undefined);
    const custom = stringErr.exec(
      () => undefined,
      async error => new Error(`mapped:${error}`),
    );

    // Assert
    (await preserved.unwrapErr()).should.equal(nativeError);
    (await normalized.unwrapErr()).message.should.equal('{"code":4}');
    (await custom.unwrapErr()).message.should.equal('mapped:raw');
  });
});

describe('Result type surface', () => {
  it('should expose the interface separately from its concrete implementation', async () => {
    // Arrange
    const value: Result<number, string> = Ok<number, string>(10);

    // Act
    const concrete = value as KResult<number, string>;

    // Assert
    concrete.should.be.instanceof(KResult);
    (await concrete.unwrap()).should.equal(10);
  });
});
