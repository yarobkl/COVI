/** Key figure tile: title, value and caption. */
export function Kpi({ t, v, s }: { t: string; v: string; s: string }) {
  return (
    <div className="kpi">
      <span>{t}</span>
      <b>{v}</b>
      <small>{s}</small>
    </div>
  )
}
