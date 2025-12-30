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
const PUBLIC_PROVIDER = "https://eth-sepolia.g.alchemy.com/v2/d6k6YyQm-UObQbgsOoj96" //own RPC to read chain state before a wallet connects
/* -------------------------- helpers -------------------------- */
function formatAddress(addr) {
  if (!addr) return '';
  return `${addr.slice(0, 6)}…${addr.slice(-6)}`;
}

//ethers.JsonRpcProvider class to connect an RPC endpoint (e.g., Alchemy/Infura) for read-only chain access.
//class → need to new it to create an instance
//Must match the network where contract is deployed.
//ethers.getDefaultProvider() helper function It auto-creates a JsonRpcProvider using default public endpoints (Etherscan, Infura, etc.).
function getReadProvider() {
  if (PUBLIC_PROVIDER) return new ethers.JsonRpcProvider(PUBLIC_PROVIDER);
  return ethers.getDefaultProvider('sepolia'); // fallback 
}

//This is for wallet-connected provider, checking if wallet is installed on the browser 
//injected provider from wallet, which can return a Signer (so can send transactions).
//async because BrowserProvider has async methods (getSigner(), etc.)
async function getEthersProvider() {
  // if (window?.ethereum) {
  //   return new ethers.BrowserProvider(window.ethereum);
  // }
  // return ethers.getDefaultProvider("using default provider");
  //window.ethereum = injected object from browser wallet extension. The bridge between dApp and the wallet
  if (!window?.ethereum) throw new Error('No wallet found');
  return new ethers.BrowserProvider(window.ethereum);
}

// Create a contract instance with both signer and provider
function getRaffleContract(signerOrProvider) {
  //ethers.Contract lets §§§§REGRGTapp interact with a deployed smart contract as if it were a JS object.
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
  const readProviderRef = useRef(null);
  const readOnlyContractRef = useRef(null);


  /* ---------------------- refresh data from blockchain ---------------------- */
  //useMemo(() => async () => {...}, []) creates refreshFromChain once(stable reference)
  //the returned value will be assigned to refreshFromChain variable,
  //its result only changes when the dependency change, avoids unnecessary recalculation 
  //i dont want refreshFromChain to be called on every re render bcs can slow down the dapp
  const refreshFromChain = useMemo(
    () => async () => {
      try {
        //set the provider and read-only contract if not already set
        //syntax if the left side is null or undefined ?? then use the right side
        const check = "if i'm null/undefined" ?? "Then I will return instead"


        const provider = readProviderRef.current ?? (readProviderRef.current = getReadProvider());
        const readOnlyContract =
          readOnlyContractRef.current ?? (readOnlyContractRef.current = getRaffleContract(provider));

        // Pull everything from the contract in parallel
        const [
          //Array destructuring into named variables in one shot, Order is preserved
          onChainPlayers,
          onChainContractBalance,
          onChainEntranceFee,
          onChainState,
          onChainInterval,
          onChainRecentWinner,
          //Promise.all([...]) starts all 6 async calls in parallel and waits for all to finish.
          //If any rejects → the whole Promise.all rejects.
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
    //The empty array [] to never re-creates the function, avoids re-subscribing to events or loops.
  );

  /* ----------------------  restore the state and set listeners ---------------------- */
  //Initial fetch on mount
  useEffect(() => {
    let mounted = true;

    (async () => {
      try {
        // Ensure provider/contract singletons = first run they’re created, later runs they’re reused.
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

    //This doesn’t run immediately, It runs when either:Component unmounts, or Before this effect runs again(because refreshFromChain changed)
    //Setting mounted = false makes sure that if the async work resolves after unmount, you won’t call setState on an unmounted component(which would throw a React warning).
    return () => { mounted = false; };
  }, [refreshFromChain]);

  //listen for events and refresh UI
  useEffect(() => {
    let readOnlyContract = null;

    (async () => {
      try {
        //Ensure a read provider and a read-only contract exist (reuse from refs)
        const readProvider = readProviderRef.current ?? (readProviderRef.current = getReadProvider());
        readOnlyContract = readOnlyContractRef.current ?? (readOnlyContractRef.current = getRaffleContract(readProvider));
        // Immediate UI refresh when the raffle state transitions
        //Register event listeners readOnlyContract.on(
        readOnlyContract.on('WinnerPicked', async () => {
          await refreshFromChain();
        });

        // Also nice to refresh when someone enters, or when request is made
        //.on(eventName, listener) is from ethers.js Contract class.
        //It registers an event listener: when the contract emits that event onchain,  callback runs.
        readOnlyContract.on('RaffleEnter', refreshFromChain);
        readOnlyContract.on('RequestedRaffleWinner', refreshFromChain);
      } catch (e) {
        // ignore if provider not ready
      }
    })();

    return () => {
      //Before this effect runs again, remove old listeners.
      //if readOnlyContract is not null/undefined, then access .removeAllListeners Otherwise → return undefined do nothing.
      //Prevents runtime errors like Cannot read properties of undefined.
      //remove those listeners so don’t accumulate duplicates or leak memory.
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
      //Cleanup return function clears the interval
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
      //.send(method, params) is a low-level JSON-RPC call that ethers forwards to the underlying provider
      //"eth_requestAccounts" is the standard RPC method MetaMask (and wallets) expose to request user accounts.
      //empty [] means no extra parameters needed, It returns an array of addresses,
      const accounts = await provider.send('eth_requestAccounts', []);
      //If accounts exists (is not null/undefined), take element 0.
      //If accounts = [] → accounts?.[0] = undefined → fallback = null.
      //If step accounts undefined (or null), replace with null.
      setConnectedAccount(accounts?.[0] ?? null);
    } catch (err) {
      console.error(err);
      //chain of nullish coalescing.
      //First try err.shortMessage, that’s null or undefined, try err.message, If that’s also missing, use 'Failed to connect wallet'
      setTxStatus(err.shortMessage ?? err.message ?? 'Failed to connect wallet');
    }
  };
  /* --------------------------- Enter raffle button -------------------------- */
  const enterRaffle = async () => {
    if (!connectedAccount) return;
    try {

      setTxStatus('Switching to Sepolia…');

      if (window.ethereum) {
        await window.ethereum.request({
          method: 'wallet_switchEthereumChain',
          params: [{ chainId: '0xaa36a7' }], // 11155111 in hex
        });
      }

      //connects to the wallet in the browser, gives access to the blockchain through the user’s wallet (MetaMask, etc.).
      const provider = await getEthersProvider();

      //the signer represents the connected account (the wallet’s private key is held by MetaMask).
      //we don’t get the raw private key — instead, the signer can sign transactions/messages on behalf of the user.
      const signer = await provider.getSigner();

      //Wraps contract ABI + address with the signer, so any “write” function (like enterRaffle) will be signed and sent by signer wallet.
      const contract = getRaffleContract(signer);

      const feeWei = await contract.getEntranceFee();

      setTxStatus('Sending transaction…');
      //Returns a transaction object (tx) with info like hash, chainId, etc.
      const tx = await contract.enterRaffle({ value: feeWei });

      setTxStatus(`Pending: ${tx.hash}`);
      //.wait() tells ethers: “Wait until this transaction is mined and confirmed in a block.”
      //Returns a receipt object: blockNumber ,status(success / failure), gasUsed, etc.
      //Without.wait(): you just know the tx hash was sent. With.wait(): you know it actually landed in the blockchain.
      const receipt = await tx.wait();
      setTxStatus(`Confirmed in block ${receipt.blockNumber}, Hash ${tx.hash}`);

      //then after enter enraffle Pulls updated state: players count, balance, recent winner, 
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
                })}
              />


              <Stat
                label="Last winner"
                value={
                  //If both are true, run formatAddress(recentWinner
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
