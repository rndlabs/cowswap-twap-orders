import { Command, Option, InvalidOptionArgumentError } from 'commander'
import { BigNumberish, ethers, Signer, utils } from 'ethers'
import { MetaTransactionData, OperationType } from '@safe-global/safe-core-sdk-types'
import EthersAdapter from '@safe-global/safe-ethers-lib'
import SafeServiceClient from '@safe-global/safe-service-client'
import Safe from '@safe-global/safe-core-sdk'
import * as dotenv from 'dotenv'

import { GPv2Settlement__factory, SignMessageLib__factory, ERC20__factory, ConditionalOrder__factory,  } from './types'

dotenv.config()

const SIGN_MESSAGE_LIB = '0xa65387f16b013cf2af4605ad8aa5ec25a2cba3a2'
const SETTLEMENT = '0x9008D19f58AAbD9eD0D60971565AA8510560ab41'
const RELAYER = '0xC92E8bdf79f0507f65a392b0ab4667716BFE0110'

const CONDITIONAL_ORDER_TYPEHASH = '0x59a89a42026f77464983113514109ddff8e510f0e62c114303617cb5ca97e091'
// const CANCELLED_CONDITIONAL_ORDER_TYPEHASH = '0xe2d395a4176e36febca53784f02b9bf31a44db36d5688fe8fc4306e6dfa54148'
const TWAP_ORDER_STRUCT = "tuple(address sellToken,address buyToken,address receiver,uint256 partSellAmount,uint256 minPartLimit,uint256 t0,uint256 n,uint256 t,uint256 span)"

interface TWAPData {
    sellToken: string
    buyToken: string
    receiver: string
    partSellAmount: BigNumberish
    minPartLimit: BigNumberish
    t0: number
    n: number
    t: number
    span: number
}

interface RootCliOptions {
    safeAddress: string
    rpcUrl: string
    privateKey: string
}

interface TWAPCliOptions extends RootCliOptions {
    sellToken: string
    buyToken: string
    receiver: string
    totalSellAmount: string
    totalMinBuyAmount: string
    startTime: number
    numParts: number
    timeInterval: number
    span: number
}

interface CancelOrderCliOptions extends RootCliOptions {
    orderHash: string
}

/**
 * Returns the URL of the transaction service for the given chainId
 * @param chainId The chainId of the network
 * @returns The URL of the transaction service
 */
const getTxServiceUrl = (chainId: number) => {
    switch (chainId) {
        case 1:
            return 'https://safe-transaction-mainnet.safe.global/'
        case 5:
            return 'https://safe-transaction-goerli.safe.global/'
        case 100:
            return 'https://safe-transaction-xdai.safe.global/'
        default:
            throw new Error(`Unsupported chainId: ${chainId}`)
    }
}

/**
 * Returns a SafeServiceClient and Safe instance
 * @param safeAddress Address of the Safe
 * @returns SafeServiceClient and Safe instances
 */
const getSafeAndService = async (options: RootCliOptions): Promise<{
    safeService: SafeServiceClient
    safe: Safe
    signer: ethers.Signer
}> => {
    const { rpcUrl, privateKey, safeAddress } = options;

    const provider = new ethers.providers.JsonRpcProvider(rpcUrl)
    const signerOrProvider = new ethers.Wallet(privateKey, provider);
    const ethAdapter = new EthersAdapter({ ethers, signerOrProvider })

    const safeService = new SafeServiceClient({ txServiceUrl: getTxServiceUrl(await ethAdapter.getChainId()), ethAdapter })
    const safe = await Safe.create({ ethAdapter, safeAddress })

    return { safeService, safe, signer: signerOrProvider }
}

const encodeTwap = async (data: TWAPData, signer: Signer): Promise<{ digest: string, payload: string }> => {
    const payload = utils.defaultAbiCoder.encode([TWAP_ORDER_STRUCT], [data])

    // get the domain separator from the settlement contract using ethers.Contract
    const settlementContract = GPv2Settlement__factory.connect(SETTLEMENT, signer);
    const domainSeparator = await settlementContract.domainSeparator()

    const structHash = ethers.utils.keccak256(
        ethers.utils.defaultAbiCoder.encode(
            ['bytes32', 'bytes32'],
            [CONDITIONAL_ORDER_TYPEHASH, utils.keccak256(payload)]
        )
    )

    const digest = utils.keccak256(ethers.utils.solidityPack(
        ['bytes1', 'bytes1', 'bytes32', 'bytes32'],
        ['0x19', '0x01', domainSeparator, structHash]
    ))

    return { digest, payload }
}

async function createTwapOrder(options: TWAPCliOptions) {
    const { safeService, safe, signer } = await getSafeAndService(options)

    const sellToken = ERC20__factory.connect(options.sellToken, signer)
    const buyToken = ERC20__factory.connect(options.buyToken, signer)

    // calculate the part sell amount
    const totalSellAmount = utils.parseUnits(options.totalSellAmount, await sellToken.decimals())
    const partSellAmount = totalSellAmount.div(options.numParts)

    // calculate the min part limit
    const minBuyAmount = utils.parseUnits(options.totalMinBuyAmount, await buyToken.decimals())
    const minPartLimit = minBuyAmount.div(options.numParts)

    const twap: TWAPData = {
        sellToken: options.sellToken,
        buyToken: options.buyToken,
        receiver: options.receiver,
        partSellAmount,
        minPartLimit,
        t0: options.startTime,
        n: options.numParts,
        t: options.timeInterval,
        span: options.span
    }

    const { digest, payload } = await encodeTwap(twap, signer)

    const safeTransactionData: MetaTransactionData[] = [
        {
            to: SIGN_MESSAGE_LIB,
            data: SignMessageLib__factory.createInterface().encodeFunctionData('signMessage', [digest]),
            value: "0",
            operation: OperationType.DelegateCall
        },
        {
            to: twap.sellToken,
            data: ERC20__factory.createInterface().encodeFunctionData('approve', [RELAYER, totalSellAmount]),
            value: "0",
        },
        {
            to: options.safeAddress,
            data: ConditionalOrder__factory.createInterface().encodeFunctionData('dispatch', [payload]),
            value: "0",
        }
    ]
    const safeTransaction = await safe.createTransaction({
        safeTransactionData, options: { nonce: await safeService.getNextNonce(options.safeAddress) }
    })
    const safeTxHash = await safe.getTransactionHash(safeTransaction)
    const senderSignature = await safe.signTransactionHash(safeTxHash)
    await safeService.proposeTransaction({
        safeAddress: options.safeAddress,
        safeTransactionData: safeTransaction.data,
        safeTxHash,
        senderAddress: await signer.getAddress(),
        senderSignature: senderSignature.data,
    })

    console.log('Submitted transaction to the Safe')
    console.log(`SafeTxHash: ${safeTxHash}`)
    console.log(`Conditional order hash for cancelling: ${digest}`)
}

/**
 * Options that are inherited by all commands
 */
class RootCommand extends Command {
    createCommand(name?: string | undefined): Command {
        const cmd = new Command(name)
        cmd
            .addOption(
                new Option('-s, --safe-address <safeAddress>', 'Address of the Safe')
                    .env('SAFE_ADDRESS')
            )
            .addOption(
                new Option('-r --rpc-url <rpcUrl>', 'URL of the Ethereum node')
                    .env('ETH_RPC_URL')
            )
            .addOption(
                new Option('-p --private-key <privateKey>', 'Private key of the account that will sign transaction batches')
                    .env('PRIVATE_KEY')
            )
        return cmd
    }
}

function cliParseInt(value: string, _: unknown): number {
	// parseInt takes a string and an optional radix
	const parsedValue = parseInt(value, 10)
	if (isNaN(parsedValue)) {
		throw new InvalidOptionArgumentError('Not a number.')
	}
	return parsedValue
}

function cliParseAddress(value: string, _: any): string {
    // Verify that the value is a valid Ethereum address
    if (!ethers.utils.isAddress(value)) {
        throw new InvalidOptionArgumentError(`Invalid address: ${value}`)
    }

    return value
}

function cliParseDecimalNumber(value: string, _: any): string {
    // Verify that the value is a string with only digits and a single decimal point that may be a represented by a comma
    if (!/^\d+(\.\d+)?$/.test(value)) {
        throw new InvalidOptionArgumentError(`Invalid number: ${value}`)
    }

    // Replace the decimal point with a dot
    value = value.replace(',', '.')

    return value
}

/**
 * CLI entry point
 */
async function main() {
    const program = new RootCommand()
        .name('conditional-orders')
        .description('Dispatch or cancel conditional orders on Safe using CoW Protocol')
        .version('0.0.1')

    program.command('create-twap')
        .description('Create a TWAP order')
        .addOption(
            new Option('--sell-token <sellToken>', 'Address of the token to sell')
                .argParser(cliParseAddress)
        )
        .addOption(
            new Option('--buy-token <buyToken>', 'Address of the token to buy')
                .argParser(cliParseAddress)
        )
        .addOption(
            new Option('-r, --receiver <receiver>', 'Address of the receiver of the buy token')
                .default(ethers.constants.AddressZero)
        )
        .addOption(
            new Option('--total-sell-amount <totalSellAmount>', 'Total amount of the token to sell')
                .argParser(cliParseDecimalNumber)
        )
        .addOption(
            new Option('--total-min-buy-amount <totalMinBuyAmount>', 'Minimum amount of the token to buy')
                .argParser(cliParseDecimalNumber)
        )
        .addOption(
            new Option('-t0 --start-time <startTime>', 'Start time of the TWAP in UNIX epoch seconds')
                .default(Math.floor(Date.now() / 1000).toString())
                .argParser(cliParseInt)
        )
        .addOption(
            new Option('-n --num-parts <numParts>', 'Number of time intervals')
                .argParser(parseInt)
        )
        .addOption(
            new Option('-t --time-interval <frequency>', 'Duration of each time interval in seconds')
                .argParser(parseInt)
        )
        .addOption(
            new Option('-s --span <span>', 'Duration of the TWAP in seconds')
                .argParser(parseInt)
                .default(0)
        )
        .action(createTwapOrder)

    program.command('cancel-order')
        .description('Cancel an order')
        .option('--order-id <orderId>', 'ID of the order to cancel')
        .action(async (options) => {
            console.log(options)
        })

    await program.parseAsync(process.argv)
}

main()