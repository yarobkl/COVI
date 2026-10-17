/** Le logo COVI : le « C » et la pièce jaune, sur le bleu du stylo. Décoratif, le nom suit en texte. */
export function BrandMark({ size = 40 }: { size?: number }) {
  return (
    <svg
      className="brand-mark"
      viewBox="0 0 1024 1024"
      width={size}
      height={size}
      aria-hidden="true"
      focusable="false"
    >
      <rect width="1024" height="1024" rx="230" fill="#17408b" />
      <path
        d="M700 300 A270 270 0 1 0 700 724"
        fill="none"
        stroke="#fcfbf8"
        strokeWidth="136"
        strokeLinecap="round"
      />
      <circle cx="700" cy="512" r="96" fill="#ffd23f" />
    </svg>
  )
}
