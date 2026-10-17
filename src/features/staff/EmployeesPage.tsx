import { useCallback, useEffect, useState, type FormEvent } from 'react'
import { money, plural } from '../../lib/format'
import { supabase } from '../../lib/supabase'
import type { Tables } from '../../lib/database.types'
import { plannedMonthlySalaries } from './salaryMath'

type Employee = Tables<'employees'>
type CompensationMode = 'fixed' | 'commission' | 'mixed'

const modeLabels: Record<CompensationMode, string> = {
  fixed: 'Salaire fixe',
  commission: 'Commission uniquement',
  mixed: 'Fixe + commission',
}

/** Private owner-only employee directory. Salary amounts are forecasts, not paid expenses. */
export function EmployeesPage({ shopId }: { shopId: string }) {
  const [employees, setEmployees] = useState<Employee[]>([])
  const [showForm, setShowForm] = useState(false)
  const [mode, setMode] = useState<CompensationMode>('fixed')
  const [busy, setBusy] = useState(false)
  const [loading, setLoading] = useState(true)
  const [message, setMessage] = useState('')
  const [error, setError] = useState(false)

  const load = useCallback(async () => {
    const { data, error: fetchError } = await supabase
      .from('employees')
      .select('*')
      .eq('shop_id', shopId)
      .order('created_at', { ascending: false })
    if (fetchError) throw fetchError
    setEmployees(data ?? [])
  }, [shopId])

  useEffect(() => {
    let active = true
    void supabase
      .from('employees')
      .select('*')
      .eq('shop_id', shopId)
      .order('created_at', { ascending: false })
      .then(({ data, error: fetchError }) => {
        if (!active) return
        setLoading(false)
        if (fetchError) {
          setError(true)
          setMessage('Impossible de charger le personnel. Vérifiez votre connexion.')
          return
        }
        setError(false)
        setEmployees(data ?? [])
      })
    return () => {
      active = false
    }
  }, [shopId])

  const active = employees.filter((item) => item.active)
  const forecast = plannedMonthlySalaries(active)

  async function addEmployee(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (busy) return
    const form = new FormData(event.currentTarget)
    const fullName = String(form.get('full_name') ?? '').trim()
    const jobTitle = String(form.get('job_title') ?? '').trim()
    const monthlySalary = mode === 'commission' ? 0 : Number(form.get('monthly_salary'))
    const commissionPercent =
      mode === 'fixed' ? 0 : Number(form.get('commission_percent'))
    if (
      fullName.length < 2 ||
      jobTitle.length < 2 ||
      !Number.isFinite(monthlySalary) ||
      monthlySalary < 0 ||
      !Number.isFinite(commissionPercent) ||
      commissionPercent < 0 ||
      commissionPercent > 100
    ) {
      setMessage('Saisissez un nom, un poste et une rémunération valides.')
      setError(true)
      return
    }
    setBusy(true)
    setMessage('')
    try {
      const { error: insertError } = await supabase.from('employees').insert({
        shop_id: shopId,
        full_name: fullName,
        job_title: jobTitle,
        compensation_mode: mode,
        monthly_salary: monthlySalary,
        commission_percent: commissionPercent,
      })
      if (insertError) throw insertError
      await load()
      setShowForm(false)
      setMode('fixed')
      setError(false)
      setMessage('Employé ajouté à votre équipe.')
    } catch {
      setError(true)
      setMessage('Impossible d’ajouter cet employé. Réessayez.')
    } finally {
      setBusy(false)
    }
  }

  async function toggleActive(employee: Employee) {
    if (busy) return
    setBusy(true)
    setMessage('')
    try {
      const { error: updateError } = await supabase
        .from('employees')
        .update({ active: !employee.active })
        .eq('shop_id', shopId)
        .eq('id', employee.id)
      if (updateError) throw updateError
      await load()
      setError(false)
      setMessage(employee.active ? 'Employé désactivé.' : 'Employé réactivé.')
    } catch {
      setError(true)
      setMessage('Impossible de modifier cet employé. Réessayez.')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div>
      <div className="hello">
        <div>
          <h1>Personnel</h1>
          <span>Votre équipe et les rémunérations prévues, en toute confidentialité.</span>
        </div>
        <button type="button" onClick={() => setShowForm(!showForm)}>
          {showForm ? 'Fermer' : 'Ajouter un employé'}
        </button>
      </div>

      <section className="card">
        <h2>{plural(active.length, 'employé')} en activité</h2>
        <p>Salaires fixes prévus par mois : <strong>{money(forecast)}</strong></p>
        <small>
          Ce montant ne comprend pas les commissions variables. Aucun salaire n’est marqué payé
          et aucune charge n’est créée automatiquement.
        </small>
      </section>

      {showForm && (
        <form className="card formgrid" onSubmit={(event) => void addEmployee(event)}>
          <div className="span2"><h2>Ajouter un membre de l’équipe</h2></div>
          <label>
            Nom de l’employé
            <input name="full_name" minLength={2} maxLength={120} required />
          </label>
          <label>
            Poste
            <input name="job_title" minLength={2} maxLength={100} required
              placeholder="Ex. Vendeuse, serveur, coiffeuse" />
          </label>
          <label>
            Rémunération
            <select value={mode} onChange={(event) =>
              setMode(event.target.value as CompensationMode)}>
              {Object.entries(modeLabels).map(([value, label]) => (
                <option value={value} key={value}>{label}</option>
              ))}
            </select>
          </label>
          {mode !== 'commission' && (
            <label>
              Salaire fixe mensuel (FCFA)
              <input name="monthly_salary" type="number" min="0" step="1" required
                defaultValue="0" />
            </label>
          )}
          {mode !== 'fixed' && (
            <label>
              Commission prévue (%)
              <input name="commission_percent" type="number" min="0" max="100"
                step="0.01" required defaultValue="0" />
            </label>
          )}
          <button className="primary span2" disabled={busy}>
            {busy ? 'Enregistrement…' : 'Ajouter l’employé'}
          </button>
        </form>
      )}
      {message && (
        <p className="successmsg" role={error ? 'alert' : 'status'}>
          {message}
        </p>
      )}
      <section className="card">
        <h2>Votre équipe</h2>
        {loading ? (
          <p>Chargement du personnel…</p>
        ) : employees.length === 0 ? (
          <p>Vous n’avez pas encore ajouté d’employé.</p>
        ) : (
          <ul>
            {employees.map((employee) => (
              <li key={employee.id}>
                <p>
                  <strong>{employee.full_name}</strong> — {employee.job_title}
                  {!employee.active && ' (inactif)'}
                </p>
                <p>
                  {modeLabels[employee.compensation_mode as CompensationMode] ??
                    employee.compensation_mode}
                  {employee.monthly_salary > 0 &&
                    ` · ${money(Number(employee.monthly_salary))} / mois`}
                  {employee.commission_percent > 0 &&
                    ` · ${employee.commission_percent} %`}
                </p>
                <button type="button" disabled={busy}
                  onClick={() => void toggleActive(employee)}>
                  {employee.active ? 'Désactiver' : 'Réactiver'}
                </button>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  )
}
