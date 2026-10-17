import { describe, expect, it } from 'vitest'
import { plannedMonthlySalaries } from './salaryMath'

describe('planned monthly salaries', () => {
  it('counts active fixed and mixed staff, not inactive or commission-only staff', () => {
    expect(
      plannedMonthlySalaries([
        { active: true, compensation_mode: 'fixed', monthly_salary: 80000 },
        { active: true, compensation_mode: 'mixed', monthly_salary: 65000 },
        { active: true, compensation_mode: 'commission', monthly_salary: 0 },
        { active: false, compensation_mode: 'fixed', monthly_salary: 100000 },
      ]),
    ).toBe(145000)
  })

  it('does not turn forecast salary into an expense or invent commissions', () => {
    expect(plannedMonthlySalaries([])).toBe(0)
  })
})
