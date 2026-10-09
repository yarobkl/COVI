// Calendar keys in the device's local time zone (toISOString() would shift them to UTC).
const pad = (n: number) => String(n).padStart(2, '0')
export const localMonth = (d: Date = new Date()) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}`
export const localDay = (d: Date = new Date()) => `${localMonth(d)}-${pad(d.getDate())}`
