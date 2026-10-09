import { act, cleanup, renderHook, waitFor } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { useAsyncData } from './useAsyncData'

afterEach(cleanup)

describe('useAsyncData', () => {
  it('exposes the loaded data', async () => {
    const load = vi.fn().mockResolvedValue(42)
    const { result } = renderHook(() => useAsyncData(load))
    expect(result.current.data).toBeNull()
    await waitFor(() => expect(result.current.data).toBe(42))
    expect(result.current.error).toBe(false)
  })

  it('flags a failure and loads again on retry', async () => {
    const load = vi.fn().mockRejectedValueOnce(new Error('Failed to fetch')).mockResolvedValue('ok')
    const { result } = renderHook(() => useAsyncData(load))
    await waitFor(() => expect(result.current.error).toBe(true))
    expect(result.current.data).toBeNull()
    act(() => result.current.retry())
    expect(result.current.error).toBe(false)
    await waitFor(() => expect(result.current.data).toBe('ok'))
    expect(load).toHaveBeenCalledTimes(2)
  })

  it('ignores a result that arrives after unmount', async () => {
    let resolve: (value: string) => void = () => {}
    const load = () => new Promise<string>((r) => (resolve = r))
    const { result, unmount } = renderHook(() => useAsyncData(load))
    unmount()
    resolve('late')
    await Promise.resolve()
    expect(result.current.data).toBeNull()
  })
})
