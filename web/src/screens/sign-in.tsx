import { type FormEvent, useState } from 'react';
import { GitHubMark, GoogleMark } from '../components/brand-marks.tsx';
import { Button } from '../components/button.tsx';
import { ErrorSummary } from '../components/error-summary.tsx';
import { TextField } from '../components/field.tsx';
import { Keypad } from '../components/keypad.tsx';
import { Logo } from '../components/logo.tsx';
import { authClient, followRedirect } from '../lib/auth-client.ts';
import { navigate } from '../lib/router.ts';
import { useDraft } from '../lib/use-draft.ts';

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const CODE_LENGTH = 6;
const EMPTY_DRAFT = { email: '' };

type FieldError = { field: string; message: string };

function emailError(email: string): string | undefined {
  if (email.trim() === '') return 'Enter your email address.';
  return EMAIL.test(email.trim()) ? undefined : 'Enter an email like name@example.com.';
}

function codeError(code: string): string | undefined {
  return /^\d{6}$/.test(code) ? undefined : `Enter the ${CODE_LENGTH}-digit code from the email.`;
}

export function SignInScreen() {
  const [draft, setDraft, clearDraft] = useDraft('sign-in', EMPTY_DRAFT);
  const [step, setStep] = useState<'email' | 'code'>('email');
  const [code, setCode] = useState('');
  const [touched, setTouched] = useState(false);
  const [pending, setPending] = useState<string | undefined>();
  const [summary, setSummary] = useState<FieldError[]>([]);
  const [serverError, setServerError] = useState<string | undefined>();

  const finish = (data: unknown) => {
    clearDraft();
    if (!followRedirect(data)) navigate('/', true);
  };

  const sendCode = async (event: FormEvent) => {
    event.preventDefault();
    setTouched(true);
    const error = emailError(draft.email);
    setSummary(error ? [{ field: 'email', message: error }] : []);
    if (error) return;
    setPending('email');
    setServerError(undefined);
    const result = await authClient.emailOtp.sendVerificationOtp({ email: draft.email.trim(), type: 'sign-in' });
    setPending(undefined);
    if (result.error) {
      setServerError(result.error.message ?? 'We could not send the code. Try again in a moment.');
      return;
    }
    setTouched(false);
    setStep('code');
  };

  const verifyCode = async (event: FormEvent) => {
    event.preventDefault();
    setTouched(true);
    const error = codeError(code);
    setSummary(error ? [{ field: 'code', message: error }] : []);
    if (error) return;
    setPending('code');
    setServerError(undefined);
    const result = await authClient.signIn.emailOtp({ email: draft.email.trim(), otp: code });
    setPending(undefined);
    if (result.error) {
      setServerError(result.error.message ?? 'That code did not work. Check it, or send a new one.');
      return;
    }
    finish(result.data);
  };

  const social = async (provider: 'github' | 'google') => {
    setPending(provider);
    setServerError(undefined);
    const result = await authClient.signIn.social({ provider, callbackURL: '/' });
    if (result.error) {
      setPending(undefined);
      setServerError(result.error.message ?? 'Sign-in did not start. Try again.');
    }
  };

  return (
    <main className="flex min-h-dvh items-start justify-center sm:items-center sm:p-8">
      <section className="flex w-full flex-col gap-6 px-4 pt-[max(2rem,env(safe-area-inset-top))] pb-[max(1.5rem,env(safe-area-inset-bottom))] sm:max-w-md sm:rounded-panel sm:border sm:border-border sm:bg-surface sm:p-8 sm:shadow-panel">
        <header className="flex flex-col items-start gap-3">
          <Logo className="size-10" />
          <h1 className="font-semibold text-2xl tracking-tight">Sign in</h1>
          <p className="text-fg-soft">
            {step === 'email'
              ? 'We will email you a sign-in code.'
              : `Enter the code we sent to ${draft.email.trim()}.`}
          </p>
        </header>

        <ErrorSummary errors={summary} />
        {serverError ? (
          <p role="alert" className="rounded-control border border-err-border bg-err-bg p-3 text-err">
            {serverError}
          </p>
        ) : null}

        {step === 'email' ? (
          <form noValidate onSubmit={sendCode} className="flex flex-col gap-4">
            <TextField
              id="email"
              label="Email"
              type="email"
              autoComplete="email"
              inputMode="email"
              enterKeyHint="send"
              value={draft.email}
              error={touched ? emailError(draft.email) : undefined}
              onChange={event => setDraft({ email: event.target.value })}
              onBlur={() => setTouched(true)}
            />
            <Button type="submit" variant="primary" pending={pending === 'email'}>
              Email me a code
            </Button>
          </form>
        ) : (
          <form noValidate onSubmit={verifyCode} className="flex flex-col gap-4">
            <TextField
              id="code"
              label="Sign-in code"
              autoComplete="one-time-code"
              inputMode="none"
              enterKeyHint="go"
              maxLength={CODE_LENGTH}
              className="tracking-[0.4em]"
              value={code}
              error={touched ? codeError(code) : undefined}
              onChange={event => setCode(event.target.value.replace(/\D/g, '').slice(0, CODE_LENGTH))}
            />
            <Keypad value={code} maxLength={CODE_LENGTH} onChange={setCode} />
            <div className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-between">
              <Button variant="ghost" onClick={() => setStep('email')}>
                Use a different email
              </Button>
              <Button type="submit" variant="primary" pending={pending === 'code'}>
                Sign in
              </Button>
            </div>
          </form>
        )}

        <div className="flex items-center gap-3 text-muted text-sm">
          <span className="h-px flex-1 bg-border" />
          or
          <span className="h-px flex-1 bg-border" />
        </div>
        <div className="flex flex-col gap-2">
          <Button pending={pending === 'github'} onClick={() => social('github')}>
            {pending === 'github' ? null : <GitHubMark />}
            Continue with GitHub
          </Button>
          <Button pending={pending === 'google'} onClick={() => social('google')}>
            {pending === 'google' ? null : <GoogleMark />}
            Continue with Google
          </Button>
        </div>
      </section>
    </main>
  );
}
