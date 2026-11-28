import { useMemo, useState } from 'react'
import type { FieldControlProps } from '../../components/ui'

const COUNTRY_CODES = [
  ['CG', 'Congo-Brazzaville', '+242'], ['CD', 'RD Congo', '+243'], ['CM', 'Cameroun', '+237'],
  ['CF', 'République centrafricaine', '+236'], ['TD', 'Tchad', '+235'], ['GQ', 'Guinée équatoriale', '+240'],
  ['GA', 'Gabon', '+241'], ['FR', 'France', '+33'], ['BE', 'Belgique', '+32'], ['CH', 'Suisse', '+41'],
  ['CA', 'Canada', '+1'], ['US', 'États-Unis', '+1'], ['CI', "Côte d’Ivoire", '+225'], ['SN', 'Sénégal', '+221'],
  ['ML', 'Mali', '+223'], ['BF', 'Burkina Faso', '+226'], ['BJ', 'Bénin', '+229'], ['TG', 'Togo', '+228'],
  ['GN', 'Guinée', '+224'], ['NE', 'Niger', '+227'], ['GH', 'Ghana', '+233'], ['NG', 'Nigeria', '+234'],
  ['ZA', 'Afrique du Sud', '+27'], ['MA', 'Maroc', '+212'], ['DZ', 'Algérie', '+213'], ['TN', 'Tunisie', '+216'],
  ['EG', 'Égypte', '+20'], ['KE', 'Kenya', '+254'], ['ET', 'Éthiopie', '+251'], ['RW', 'Rwanda', '+250'],
  ['UG', 'Ouganda', '+256'], ['TZ', 'Tanzanie', '+255'], ['AO', 'Angola', '+244'], ['MZ', 'Mozambique', '+258'],
  ['BR', 'Brésil', '+55'], ['MX', 'Mexique', '+52'], ['AR', 'Argentine', '+54'], ['CL', 'Chili', '+56'],
  ['CN', 'Chine', '+86'], ['IN', 'Inde', '+91'], ['JP', 'Japon', '+81'], ['KR', 'Corée du Sud', '+82'],
  ['AU', 'Australie', '+61'], ['NZ', 'Nouvelle-Zélande', '+64'], ['AE', 'Émirats arabes unis', '+971'],
  ['SA', 'Arabie saoudite', '+966'], ['IL', 'Israël', '+972'], ['TR', 'Turquie', '+90'], ['GB', 'Royaume-Uni', '+44'],
  ['DE', 'Allemagne', '+49'], ['ES', 'Espagne', '+34'], ['IT', 'Italie', '+39'], ['PT', 'Portugal', '+351'],
  ['NL', 'Pays-Bas', '+31'], ['SE', 'Suède', '+46'], ['NO', 'Norvège', '+47'], ['DK', 'Danemark', '+45'],
  ['FI', 'Finlande', '+358'], ['IE', 'Irlande', '+353'], ['AT', 'Autriche', '+43'], ['PL', 'Pologne', '+48'],
  ['RU', 'Russie', '+7'], ['UA', 'Ukraine', '+380'], ['SG', 'Singapour', '+65'],
] as const

export function PhoneInput({ control, value, onChange }: { control: FieldControlProps; value: string; onChange: (value: string) => void }) {
  const parsed = useMemo(() => COUNTRY_CODES.find(([, , code]) => value.startsWith(code)) ?? COUNTRY_CODES[0], [value])
  const [country, setCountry] = useState<string>(parsed[2])
  const national = value.startsWith(country) ? value.slice(country.length).replace(/\D/g, '') : value.replace(/^\+\d{1,3}/, '').replace(/\D/g, '')
  return (
    <div className="phone-input">
      <select aria-label="Indicatif du pays" value={country} onChange={(event) => { setCountry(event.target.value); onChange(`${event.target.value}${national}`) }}>
        {COUNTRY_CODES.map(([iso, label, code]) => <option key={`${iso}-${code}`} value={code}>{label} ({code})</option>)}
      </select>
      <input
        {...control}
        className="input"
        name="phone-national"
        type="tel"
        inputMode="numeric"
        autoComplete="tel-national"
        placeholder="06 12 34 56 78"
        required
        value={national}
        onChange={(event) => {
          const raw = event.target.value.trim()
          const digits = raw.startsWith(country) ? raw.slice(country.length) : raw
          onChange(`${country}${digits.replace(/\D/g, '')}`)
        }}
      />
      <input type="hidden" name="phone" value={`${country}${national}`} />
    </div>
  )
}
