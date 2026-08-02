export const getVersion: () => string;
export const runGoSmoke: (rounds: number) => boolean;
export const runGoLifecycle: (cycles: number) => boolean;
export const startGoSmoke: () => boolean;
export const stopGoSmoke: () => boolean;
export const getGoSmokeTicks: () => number;
