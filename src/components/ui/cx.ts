/** Joins the truthy class names: `cx('btn', busy && 'is-busy')`. */
export const cx = (...names: (string | false | null | undefined)[]) =>
  names.filter(Boolean).join(' ')
