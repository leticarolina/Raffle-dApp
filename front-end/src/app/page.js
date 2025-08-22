'use client';

import Image from "next/image";
import { ethers } from "ethers";
import { useEffect, useState, useMemo, useRef } from "react";
import Stat from "./components/Stat.jsx";
import raffleTicket from "@/app/images/raffle1.png";


const ABI = [
  'function getNumberOfPlayers() view returns (uint256)',
  'function getInterval() view returns (uint256)',
  'function getLastTimeStamp() view returns (uint256)',
  'function getEntranceFee() view returns (uint256)',
  'function getRecentWinner() view returns (address)',
  'function getRaffleState() view returns (uint256)',
  'function enterRaffle() payable',
  'event WinnerPicked(address indexed winner)',
  'event RequestedRaffleWinner(uint256 indexed requestId)',
  'event RaffleEnter(address indexed player)',
];

const CONTRACT_ADDRESS = "0xdB9ED786cAF806b929C52eDC18a350eDAB9ADbfa";
const PUBLIC_PROVIDER = "https://eth-sepolia.g.alchemy.com/v2/d6k6YyQm-UObQbgsOoj96"
/* -------------------------- helpers -------------------------- */
function formatAddress(addr) {
  if (!addr) return '';
  return `${addr.slice(0, 6)}…${addr.slice(-6)}`;
}

function getReadProvider() {
  if (PUBLIC_PROVIDER) return new ethers.JsonRpcProvider(PUBLIC_PROVIDER);
  return ethers.getDefaultProvider('sepolia'); // fallback 
}

//checking if wallet is installed on the browser
async function getEthersProvider() {
  // if (window?.ethereum) {
  //   return new ethers.BrowserProvider(window.ethereum);
  // }
  // return ethers.getDefaultProvider("using default provider");
  if (!window?.ethereum) throw new Error('No wallet found');
  return new ethers.BrowserProvider(window.ethereum);
}

// Create a contract instance with both signer and provider
function getRaffleContract(signerOrProvider) {
  return new ethers.Contract(CONTRACT_ADDRESS, ABI, signerOrProvider);
}


/* -------------------------- main -------------------------- */
export default function Home() {
  // State variables
  const [connectedAccount, setConnectedAccount] = useState(null);
  const [playersCount, setPlayersCount] = useState(0);
  const [prizePoolEth, setPrizePoolEth] = useState('0');
  const [entranceFeeEth, setEntranceFeeEth] = useState('0');
  const [recentWinner, setRecentWinner] = useState('');
  const [raffleIsOpen, setRaffleIsOpen] = useState(true); // OPEN=0, CALCULATING=1
  const [intervalMinutes, setIntervalMinutes] = useState(0);
  const [txStatus, setTxStatus] = useState(''); // Transaction status message
  // Refs to keep provider and read-only contract across renders
  // const providerRef = useRef(null);
  const readProviderRef = useRef(null);
  const readOnlyContractRef = useRef(null);


  /* ---------------------- refresh data from blockchain ---------------------- */
  const refreshFromChain = useMemo(
    () => async () => {
      try {
        //set the provider and read-only contract if not already set
        // const provider =
        //   providerRef.current ?? (providerRef.current = getReadProvider());
        const provider = readProviderRef.current ?? (readProviderRef.current = getReadProvider());
        const readOnlyContract =
          readOnlyContractRef.current ?? (readOnlyContractRef.current = getRaffleContract(provider));

        // Pull everything from the contract in parallel
        const [
          onChainPlayers,
          onChainContractBalance,
          onChainEntranceFee,
          onChainState,
          onChainInterval,
          onChainRecentWinner,
        ] = await Promise.all([
          readOnlyContract.getNumberOfPlayers(),
          provider.getBalance(CONTRACT_ADDRESS),
          readOnlyContract.getEntranceFee(),
          readOnlyContract.getRaffleState(),
          readOnlyContract.getInterval(),
          readOnlyContract.getRecentWinner(),
        ]);

        // Commit state
        setPlayersCount(Number(onChainPlayers));
        setPrizePoolEth(ethers.formatEther(onChainContractBalance));
        setEntranceFeeEth(ethers.formatEther(onChainEntranceFee));
        setRaffleIsOpen(Number(onChainState) === 0); //True when open, 0 = OPEN, 1 = CALCULATING
        setRecentWinner(onChainRecentWinner);
        setIntervalMinutes(Math.floor(Number(onChainInterval) / 60)); // Convert interval seconds to minutes
      } catch (err) {
        console.error('refreshFromChain:', err);
      }
    },
    []
  );

  /* ----------------------  restore the state and set listeners ---------------------- */
  //Initial fetch on mount
  useEffect(() => {
    let mounted = true;

    (async () => {
      try {
        // Ensure provider/contract singletons
        // const provider =
        //   providerRef.current ?? (providerRef.current = await getEthersProvider());
        // readOnlyContractRef.current ??= getRaffleContract(provider);
        const readProvider =
          readProviderRef.current ?? (readProviderRef.current = getReadProvider());
        readOnlyContractRef.current ??= getRaffleContract(readProvider);

        if (mounted) {
          await refreshFromChain(); // populate fee, players, last winner, etc.
        }
      } catch (e) {
        console.error(e);
      }
    })();

    return () => { mounted = false; };
  }, [refreshFromChain]);

  //listen for events and refresh UI
  useEffect(() => {
    let readOnlyContract = null;

    (async () => {
      try {
        // const provider =
        //   providerRef.current ?? (providerRef.current = await getEthersProvider());
        const readProvider = readProviderRef.current ?? (readProviderRef.current = getReadProvider());
        // readOnlyContract =
        //   readOnlyContractRef.current ?? (readOnlyContractRef.current = getRaffleContract(provider));
        readOnlyContract = readOnlyContractRef.current ?? (readOnlyContractRef.current = getRaffleContract(readProvider));
        // Immediate UI refresh when the raffle state transitions
        readOnlyContract.on('WinnerPicked', async () => {
          await refreshFromChain();
        });

        // Also nice to refresh when someone enters, or when request is made
        readOnlyContract.on('RaffleEnter', refreshFromChain);
        readOnlyContract.on('RequestedRaffleWinner', refreshFromChain);
      } catch (e) {
        // ignore if provider not ready
      }
    })();

    return () => {
      //Before this effect runs again, remove old listeners.
      if (readOnlyContract?.removeAllListeners) {
        readOnlyContract.removeAllListeners('WinnerPicked');
        readOnlyContract.removeAllListeners('RaffleEnter');
        readOnlyContract.removeAllListeners('RequestedRaffleWinner');
      }
    };
  }, [refreshFromChain]);

  // Refresh every 2.5 seconds while raffle is calculating to ensure UI is up-to-date
  useEffect(() => {
    if (!raffleIsOpen) {
      const id = setInterval(refreshFromChain, 2500); // fast while drawing
      return () => clearInterval(id);
    }
  }, [raffleIsOpen, refreshFromChain]);


  /* ------------------- Connect wallet button ------------------- */
  const connectWallet = async () => {
    try {
      //provider.send is the way to call RPC methods directly.
      // 'eth_requestAccounts' = standard Ethereum JSON-RPC method that asks the user’s wallet for permission to connect.
      // const provider =
      //   providerRef.current ?? (providerRef.current = await getEthersProvider());
      // const accounts = await provider.send('eth_requestAccounts', []);
      // setConnectedAccount(accounts?.[0] ?? null);
      const provider = await getEthersProvider();
      const accounts = await provider.send('eth_requestAccounts', []);
      setConnectedAccount(accounts?.[0] ?? null);
    } catch (err) {
      console.error(err);
      setTxStatus(err.shortMessage ?? err.message ?? 'Failed to connect wallet');
    }
  };
  /* --------------------------- Enter raffle button -------------------------- */
  const enterRaffle = async () => {
    if (!connectedAccount) return;
    try {
      setTxStatus('Connecting wallet…');

      // const provider =
      //   providerRef.current ?? (providerRef.current = await getEthersProvider());
      // const signer = await provider.getSigner();

      const provider = await getEthersProvider();
      const signer = await provider.getSigner();
      const contract = getRaffleContract(signer);

      const feeWei = await contract.getEntranceFee();

      setTxStatus('Sending transaction…');
      const tx = await contract.enterRaffle({ value: feeWei });
      setTxStatus(`Pending: ${tx.hash}`);
      const receipt = await tx.wait();
      setTxStatus(`Confirmed in block ${receipt.blockNumber}`);

      await refreshFromChain();
    } catch (err) {
      setTxStatus('Raffle is drawing a winner. Please wait and try again.');
    }

  };

  /* -------------------------- Raffle status label -------------------------- */
  function raffleStatusLabel({ isOpen, playersCount }) {
    // Not OPEN → Chainlink is drawing & fulfilling
    if (!isOpen) return "Drawing winner…";

    // OPEN but no entrants yet
    if (playersCount === 0) return "Waiting for players";

    // - Interval is only 120 seconds, so if we are here, it means the raffle is open and has players
    return "Open (automation may run any moment)";
  }

  /* ----------------------------------- UI ----------------------------------- */
  return (
    <main className="min-h-screen flex flex-col bg-[#F5EFE7]">

      {/* NAV BAR */}
      <header className="w-full">
        <div className="mx-auto px-8 pt-4 flex items-center justify-between md:px-20">
          <h1 className="text-2xl text-[#213555] font-semibold">Web3 Raffle</h1>

          {connectedAccount ? (
            <span className="px-3 py-1 text-s rounded-full bg-green-100 text-green-900">
              wallet: {formatAddress(connectedAccount)}
            </span>
          ) : (
            <button
              onClick={connectWallet}
              className="p-3 text-m bg-[#213555] text-white rounded-lg hover:opacity-80 transition-opacity duration-300"
            >
              Connect Wallet
            </button>
          )}
        </div>
      </header>

      {/* Centered content */}
      <section className="flex-1 flex items-center justify-center px-5">
        <div className="w-full max-w-md">
          {/* Contract address (just above the card) */}
          <div className="mb-2 text-center">
            <span className="text-xs text-gray-500">Contract:</span>{' '}
            <a
              href={`https://sepolia.etherscan.io/address/${CONTRACT_ADDRESS}`}
              target="_blank"
              rel="noopener noreferrer"
              className="text-s font-mono text-[#213555] hover:opacity-80"
            >
              {`${CONTRACT_ADDRESS.slice(0, 10)}...${CONTRACT_ADDRESS.slice(-10)}`}
            </a>
          </div>

          {/* Card */}
          <div className="rounded-2xl shadow-xl bg-white px-5 pb-5 pt-0">
            {/* Image on top */}
            <div className="relative w-full h-44 md:h-48">
              <Image
                src={raffleTicket}
                alt="Raffle ticket"
                fill
                className="object-contain"
                priority
              />
              {/* Entrance fee badge */}
              <div className="absolute top-1 right-0 rounded-md px-2 py-1">
                <span className="text-xs uppercase text-gray-500">Entrance fee</span>
                <div className="text-sm font-semibold text-[#213555] pl-2">{entranceFeeEth} ETH</div>
              </div>
            </div>

            {/* Pot */}
            <div className="mt-2 text-center">
              <div className="inline-flex items-baseline gap-2 rounded-xl bg-gray-100 px-4 py-2">
                <span className="text-xs uppercase tracking-wide text-gray-500">Pot</span>
                <span className="text-xl font-semibold text-black">{prizePoolEth} ETH</span>
              </div>
            </div>

            {/* Stats */}
            <div className="mt-6 grid md:grid-cols-2 gap-4 text-center">
              {/* <Stat label="Entrance fee" value={`${entranceFeeEth} ETH`} /> */}
              <Stat label="automation/draw interval" value={`${intervalMinutes} minutes`} />
              <Stat label="Players" value={String(playersCount)} />

              <Stat
                label="Raffle status"
                value={raffleStatusLabel({
                  isOpen: raffleIsOpen,
                  playersCount,
                  // timeLeft: secondsRemaining,
                })}
              />


              <Stat
                label="Last winner"
                value={
                  recentWinner && recentWinner !== ethers.ZeroAddress
                    ? formatAddress(recentWinner)
                    : '-'
                }
              />
            </div>
          </div>

          {/* Enter raffle button */}
          <div className="mt-6 flex justify-center">
            <button
              onClick={enterRaffle}
              disabled={!connectedAccount}
              className={`py-3 px-5 rounded-lg text-white ${connectedAccount
                ? 'bg-green-800 hover:opacity-80 transition-opacity duration-300'
                : 'bg-gray-400 cursor-not-allowed'
                }`}
            >
              {connectedAccount ? 'Enter Raffle' : 'Connect to Enter'}
            </button>
          </div>

          {/* Tx status */}
          {txStatus && (
            <p className="mt-2 text-xs text-gray-600 text-center">{txStatus}</p>
          )}
        </div>
      </section>
    </main>
  );
}
