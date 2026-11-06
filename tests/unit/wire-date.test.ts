import { describe, it } from 'bun:test';
import { Temporal } from '@js-temporal/polyfill';
import 'should';
import { WireDateCodec, WireDateError, type WireTimeZone } from '../../src/lib/wire-date';
import { expectErr, expectOk } from './support/result';

const codec = new WireDateCodec();

describe('WireDateCodec date', () => {
  it.each([{ wire: '2020-02-29' }, { wire: '1999-12-31' }, { wire: '2026-07-24' }])(
    'should round-trip Temporal.PlainDate for $wire',
    async ({ wire }) => {
      // Arrange
      const domain = await expectOk(codec.parseDate(wire));

      // Act
      const formatted = await expectOk(codec.formatDate(domain));

      // Assert
      domain.should.be.instanceof(Temporal.PlainDate);
      formatted.should.equal(wire);
      (await expectOk(codec.parseDate(formatted))).equals(domain).should.be.true();
    },
  );

  it.each([
    { wire: '2020-2-3', message: /canonical YYYY-MM-DD/ },
    { wire: '20-02-03', message: /canonical YYYY-MM-DD/ },
    { wire: '2020/02/03', message: /canonical YYYY-MM-DD/ },
    { wire: '2020-02-03T00:00:00', message: /canonical YYYY-MM-DD/ },
    { wire: '', message: /canonical YYYY-MM-DD/ },
    { wire: '2021-02-30', message: /not a valid calendar date/ },
  ])('should reject wire date "$wire"', async ({ wire, message }) => {
    // Arrange
    const input = wire;

    // Act
    const actual = await expectErr(codec.parseDate(input));

    // Assert
    actual.should.be.instanceof(WireDateError);
    actual.form.should.equal('date');
    actual.message.should.match(message);
  });

  it('should reject a domain date that cannot be emitted as YYYY-MM-DD', async () => {
    // Arrange
    const domain = Temporal.PlainDate.from('2026-07-24[u-ca=hebrew]');

    // Act
    const actual = await expectErr(codec.formatDate(domain));

    // Assert
    actual.message.should.match(/cannot be represented/);
  });
});

describe('WireDateCodec time', () => {
  it.each([{ wire: '00:00:00' }, { wire: '13:37:00' }, { wire: '23:59:59' }])(
    'should round-trip Temporal.PlainTime for $wire',
    async ({ wire }) => {
      // Arrange
      const domain = await expectOk(codec.parseTime(wire));

      // Act
      const formatted = await expectOk(codec.formatTime(domain));

      // Assert
      domain.should.be.instanceof(Temporal.PlainTime);
      formatted.should.equal(wire);
      (await expectOk(codec.parseTime(formatted))).equals(domain).should.be.true();
    },
  );

  it.each([
    { wire: '01:02', message: /canonical HH:mm:ss/ },
    { wire: '01:02:03.5', message: /canonical HH:mm:ss/ },
    { wire: '01:02:03Z', message: /canonical HH:mm:ss/ },
    { wire: '01:02:03+08:00', message: /canonical HH:mm:ss/ },
    { wire: '1:2:3', message: /canonical HH:mm:ss/ },
    { wire: '25:00:00', message: /not a valid time of day/ },
    { wire: '23:59:60', message: /does not round-trip/ },
    { wire: '00:00:60', message: /does not round-trip/ },
  ])('should reject wire time "$wire"', async ({ wire, message }) => {
    // Arrange
    const input = wire;

    // Act
    const actual = await expectErr(codec.parseTime(input));

    // Assert
    actual.form.should.equal('time');
    actual.message.should.match(message);
  });

  it('should reject a domain time with sub-second precision', async () => {
    // Arrange
    const domain = Temporal.PlainTime.from('01:02:03.456');

    // Act
    const actual = await expectErr(codec.formatTime(domain));

    // Assert
    actual.message.should.match(/whole-second precision/);
  });
});

describe('WireDateCodec datetime', () => {
  it.each([
    { wire: '1970-01-01T00:00:00Z' },
    { wire: '2020-01-02T03:04:05Z' },
    { wire: '2026-07-24T23:59:59Z' },
    { wire: '2026-07-24T23:59:59.123456789Z' },
  ])('should round-trip Temporal.Instant for $wire', async ({ wire }) => {
    // Arrange
    const domain = await expectOk(codec.parseDateTime(wire));

    // Act
    const formatted = await expectOk(codec.formatDateTime(domain));

    // Assert
    domain.should.be.instanceof(Temporal.Instant);
    formatted.should.equal(wire);
    (await expectOk(codec.parseDateTime(formatted))).equals(domain).should.be.true();
  });

  it.each([
    { wire: '2020-01-02T03:04:05', message: /canonical RFC 3339 UTC instant/ },
    { wire: '2020-01-02T03:04:05+08:00', message: /canonical RFC 3339 UTC instant/ },
    { wire: '2020-01-02 03:04:05Z', message: /canonical RFC 3339 UTC instant/ },
    { wire: '2020-01-02T03:04Z', message: /canonical RFC 3339 UTC instant/ },
    { wire: '2020-13-01T00:00:00Z', message: /not a valid instant/ },
    { wire: '2020-01-02T03:04:05.120Z', message: /canonical fractional precision/ },
  ])('should reject wire datetime "$wire"', async ({ wire, message }) => {
    // Arrange
    const input = wire;

    // Act
    const actual = await expectErr(codec.parseDateTime(input));

    // Assert
    actual.form.should.equal('datetime');
    actual.message.should.match(message);
  });

  it('should keep the parse cause on an impossible instant', async () => {
    // Arrange
    const input = '2020-13-01T00:00:00Z';

    // Act
    const actual = await expectErr(codec.parseDateTime(input));

    // Assert
    (actual.cause as Error).should.be.instanceof(RangeError);
  });

  it('should reject a domain instant outside the RFC 3339 year range', async () => {
    // Arrange
    const domain = Temporal.Instant.from('+010000-01-01T00:00:00Z');

    // Act
    const actual = await expectErr(codec.formatDateTime(domain));

    // Assert
    actual.message.should.match(/outside the canonical RFC 3339 year range/);
  });
});

describe('WireDateCodec duration', () => {
  it.each([{ wire: 'PT0S' }, { wire: 'P1DT2H' }, { wire: 'P1Y2M3DT4H5M6S' }, { wire: 'PT1.5S' }, { wire: '-P1D' }])(
    'should round-trip Temporal.Duration for $wire',
    async ({ wire }) => {
      // Arrange
      const domain = await expectOk(codec.parseDuration(wire));

      // Act
      const formatted = codec.formatDuration(domain);

      // Assert
      domain.should.be.instanceof(Temporal.Duration);
      formatted.should.equal(wire);
      codec.formatDuration(await expectOk(codec.parseDuration(formatted))).should.equal(wire);
    },
  );

  it.each([
    { wire: 'P', message: /not a valid ISO 8601 duration/ },
    { wire: 'abc', message: /not a valid ISO 8601 duration/ },
    { wire: '1D', message: /not a valid ISO 8601 duration/ },
    { wire: '', message: /not a valid ISO 8601 duration/ },
    { wire: 'p1dt2h', message: /canonical Temporal spelling/ },
    { wire: 'PT01H', message: /canonical Temporal spelling/ },
    { wire: 'P0D', message: /canonical Temporal spelling/ },
  ])('should reject wire duration "$wire"', async ({ wire, message }) => {
    // Arrange
    const input = wire;

    // Act
    const actual = await expectErr(codec.parseDuration(input));

    // Assert
    actual.form.should.equal('duration');
    actual.message.should.match(message);
  });
});

describe('WireDateCodec timezone', () => {
  it.each([
    { wire: 'UTC' },
    { wire: 'Asia/Singapore' },
    { wire: 'America/New_York' },
    { wire: 'Europe/London' },
    { wire: 'Australia/Lord_Howe' },
  ])('should round-trip the IANA id $wire', async ({ wire }) => {
    // Arrange
    const domain = await expectOk(codec.parseTimeZone(wire));

    // Act
    const formatted = await expectOk(codec.formatTimeZone(domain));

    // Assert
    formatted.should.equal(wire);
  });

  it.each([
    { wire: 'America/New_York', winter: '-05:00', summer: '-04:00' },
    { wire: 'Europe/London', winter: '+00:00', summer: '+01:00' },
  ])('should keep the DST rules of $wire', async ({ wire, winter, summer }) => {
    // Arrange
    const zone = await expectOk(codec.parseTimeZone(wire));
    const january = await expectOk(codec.parseDateTime('2021-01-01T12:00:00Z'));
    const july = await expectOk(codec.parseDateTime('2021-07-01T12:00:00Z'));

    // Act
    const offsets = [january, july].map(instant => new Temporal.ZonedDateTime(instant.epochNanoseconds, zone).offset);

    // Assert
    offsets.should.deepEqual([winter, summer]);
  });

  it.each([
    { wire: 'Not/AZone', message: /not a known IANA time zone/ },
    { wire: '', message: /not a known IANA time zone/ },
    { wire: '+01:00', message: /not a fixed offset/ },
    { wire: 'asia/singapore', message: /case-normalized IANA id "Asia\/Singapore"/ },
  ])('should reject wire timezone "$wire"', async ({ wire, message }) => {
    // Arrange
    const input = wire;

    // Act
    const actual = await expectErr(codec.parseTimeZone(input));

    // Assert
    actual.form.should.equal('timezone');
    actual.message.should.match(message);
  });

  it('should re-validate a forged brand at the format boundary', async () => {
    // Arrange
    const zone = 'Not/AZone' as WireTimeZone;

    // Act
    const actual = await expectErr(codec.formatTimeZone(zone));

    // Assert
    actual.message.should.match(/not a known IANA time zone/);
  });
});
