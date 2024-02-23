import { ConnectButton } from "@mysten/dapp-kit"
import './App.css'

import Chip from "./components/Chip"

function App() {
  return (
    <div className="App">
      <header className="App-header">
        <ConnectButton className="connect-button"/>
      </header>
      <Chip value={100} onClick={() => console.log('Chip clicked')} />
    </div>
  )
  
}

export default App
