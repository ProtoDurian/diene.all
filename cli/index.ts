#!/usr/bin/env bun
import pkg from '../package.json' with { type: 'json' };
import { AseityCli } from './app';
import { CliConfig, EnvConfigSource } from './config';
import { Wiring } from './wiring';

const wiring = new Wiring(new CliConfig(new EnvConfigSource(process.env)));
const cli = new AseityCli({
  version: pkg.version,
  stdout: process.stdout,
  stderr: process.stderr,
  migrate: directory => wiring.migrate(directory),
  forkService: () => wiring.forkService(),
});

process.exitCode = await cli.run(process.argv.slice(2));
