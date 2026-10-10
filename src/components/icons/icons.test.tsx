import { cleanup, render } from '@testing-library/react'
import { afterEach, describe, expect, it } from 'vitest'
import * as icons from '.'

afterEach(cleanup)

describe('icons', () => {
  const entries = Object.entries(icons) as [string, (p: icons.IconProps) => React.ReactElement][]

  it('are decorative 24 px line drawings with the system stroke', () => {
    expect(entries.length).toBeGreaterThanOrEqual(20)
    for (const [name, IconComponent] of entries) {
      const { container } = render(<IconComponent className="icon--sm" />)
      const svg = container.querySelector('svg')
      expect(svg, name).not.toBeNull()
      expect(svg!.getAttribute('aria-hidden')).toBe('true')
      expect(svg!.getAttribute('stroke-width')).toBe('1.75')
      expect(svg!.getAttribute('viewBox')).toBe('0 0 24 24')
      expect(svg!.getAttribute('class')).toBe('icon icon--sm')
      cleanup()
    }
  })
})
