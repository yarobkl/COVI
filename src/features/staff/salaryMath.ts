/** Planned fixed monthly salaries only. Commission payments are NOT inferred from turnover. */
export type FixedCompensation = {
  active: boolean
  compensation_mode: string
  monthly_salary: number
}

export function plannedMonthlySalaries(employees: readonly FixedCompensation[]): number {
  return employees
    .filter((employee) => employee.active && employee.compensation_mode !== 'commission')
    .reduce((sum, employee) => sum + (Number(employee.monthly_salary) || 0), 0)
}
