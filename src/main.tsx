import { createRoot } from 'react-dom/client'
import './styles.css'
import './haptics.css'
import { installButtonFeedback } from './lib/haptics'
import { Root } from './app/Root'

installButtonFeedback()
createRoot(document.getElementById('root')!).render(<Root />)
