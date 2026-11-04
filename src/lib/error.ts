class UnwrapError extends Error {
  type: 'Expected Ok got Error' | 'Expected Err got Ok' | 'Expected Some got None';
  monadType: 'result' | 'option';

  constructor(
    message: string,
    monadType: 'result' | 'option',
    type: 'Expected Ok got Error' | 'Expected Err got Ok' | 'Expected Some got None',
  ) {
    super(message);
    this.type = type;
    this.monadType = monadType;
    this.name = 'UnwrapError';
  }
}

export { UnwrapError };

type DUI1<T extends Array<[string, unknown]>> = {
  [K in keyof T]: {
    __kind: T[K][0];
    value: T[K][1];
  };
};
type DU2<T extends DUI1<X>, X extends Array<[string, unknown]>> = T[number];
type DU<T extends Array<[string, unknown]>> = DU2<DUI1<T>, T>;

export type { DU };
