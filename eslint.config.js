import js from '@eslint/js'
import { defineConfig } from 'eslint/config'
import globals from 'globals'
import reactHooks from 'eslint-plugin-react-hooks'
import reactRefresh from 'eslint-plugin-react-refresh'
import tseslint from 'typescript-eslint'

// typescript-eslint needs the TypeScript compiler API, which TypeScript 7 does not ship.
// package.json follows the TypeScript 7 side-by-side setup: `typescript` is an alias of the
// TypeScript 6 API package (@typescript/typescript6) used only by the linter, while the compiler
// (`tsc -b`) is TypeScript 7, installed as `@typescript/native`.
export default defineConfig(
  { ignores: ['dist', 'src-tauri', 'supabase'] },
  {
    files: ['**/*.{ts,tsx}'],
    extends: [js.configs.recommended, tseslint.configs.recommended],
    languageOptions: { ecmaVersion: 2022, globals: globals.browser },
    plugins: { 'react-hooks': reactHooks, 'react-refresh': reactRefresh },
    rules: {
      ...reactHooks.configs.recommended.rules,
      'react-refresh/only-export-components': ['warn', { allowConstantExport: true }],
    },
  },
  {
    files: ['**/*.{js,mjs}'],
    extends: [js.configs.recommended],
    languageOptions: { ecmaVersion: 2022, globals: { ...globals.node, ...globals.browser } },
  },
)
