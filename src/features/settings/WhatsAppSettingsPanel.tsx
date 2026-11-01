import { useEffect, useState } from 'react'
import { Button, Sheet } from '../../components/ui'
import { supabase } from '../../lib/supabase'

export function WhatsAppSettingsPanel({ shopId }: { shopId: string }) {
  const [enabled, setEnabled] = useState(false)
  const [dailyReport, setDailyReport] = useState(true)
  const [reportTime, setReportTime] = useState('21:30')
  const [phone, setPhone] = useState('')
  const [timezone, setTimezone] = useState('Africa/Brazzaville')
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState('')
  // The generated Supabase types will be refreshed when the WhatsApp migration is applied.
  const whatsappDb = supabase as any

  useEffect(() => {
    let active = true
    void whatsappDb
      .from('whatsapp_notification_preferences')
      .select('enabled,daily_report_enabled,daily_report_time,recipient_phone,timezone')
      .eq('shop_id', shopId)
      .maybeSingle()
      .then(({ data }: { data: { enabled: boolean; daily_report_enabled: boolean; daily_report_time: string; recipient_phone: string | null; timezone: string } | null }) => {
        if (!active || !data) return
        setEnabled(data.enabled)
        setDailyReport(data.daily_report_enabled)
        setReportTime(String(data.daily_report_time).slice(0, 5))
        setPhone(data.recipient_phone ?? '')
        setTimezone(data.timezone ?? 'Africa/Brazzaville')
      })
    return () => {
      active = false
    }
  }, [shopId])

  async function save() {
    setBusy(true)
    setMessage('')
    const { error } = await whatsappDb.from('whatsapp_notification_preferences').upsert({
      shop_id: shopId,
      enabled,
      daily_report_enabled: dailyReport,
      daily_report_time: reportTime,
      timezone,
      recipient_phone: phone.trim() || null,
    })
    setBusy(false)
    setMessage(error ? 'Les réglages WhatsApp seront disponibles après la connexion Meta.' : '✓ Préférences WhatsApp enregistrées.')
  }

  return (
    <Sheet aria-labelledby="whatsapp-settings-title">
      <div className="settings-whatsapp">
        <div>
          <h2 className="section-title" id="whatsapp-settings-title">WhatsApp Business</h2>
          <p className="muted">Recevez les alertes et le bilan de fin de journée de cette boutique.</p>
        </div>
        <p className="settings-whatsapp__status">Connexion Meta : <strong>à configurer</strong></p>
        <label className="settings-whatsapp__toggle">
          <input type="checkbox" checked={enabled} onChange={(event) => setEnabled(event.target.checked)} />
          Activer les notifications WhatsApp
        </label>
        <label>
          Numéro WhatsApp Business destinataire
          <input type="tel" placeholder="+242 06 000 00 00" value={phone} onChange={(event) => setPhone(event.target.value)} />
        </label>
        <label className="settings-whatsapp__toggle">
          <input type="checkbox" checked={dailyReport} onChange={(event) => setDailyReport(event.target.checked)} />
          Recevoir le bilan quotidien
        </label>
        <label>
          Heure du bilan
          <input type="time" value={reportTime} onChange={(event) => setReportTime(event.target.value)} />
        </label>
        <label>
          Fuseau horaire
          <select value={timezone} onChange={(event) => setTimezone(event.target.value)}>
            <option value="Africa/Brazzaville">Brazzaville (UTC+1)</option>
            <option value="Europe/Paris">Paris (UTC+1/+2)</option>
            <option value="Africa/Kinshasa">Kinshasa (UTC+1)</option>
          </select>
        </label>
        <Button variant="secondary" type="button" busy={busy} busyLabel="Enregistrement…" onClick={() => void save()}>
          Enregistrer les préférences
        </Button>
        {message && <p className="page-msg" role="status">{message}</p>}
      </div>
    </Sheet>
  )
}
