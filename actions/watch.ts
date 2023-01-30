import {
  ActionFn,
  BlockEvent,
  Context,
  Event,
  TransactionEvent,
} from "@tenderly/actions";
import {
  Order,
  OrderBalance,
  OrderKind,
  computeOrderUid,
} from "@cowprotocol/contracts";

import axios from "axios";
import { ethers } from "ethers";
import { ConditionalOrder__factory, GPv2Settlement__factory } from "./types";
import { Registry, OrderStatus } from "./register";
import { Logger } from "ethers/lib/utils";

export const checkForSettlement: ActionFn = async (
  context: Context,
  event: Event
) => {
  const transactionEvent = event as TransactionEvent;
  const iface = GPv2Settlement__factory.createInterface();

  const registry = await Registry.load(context, transactionEvent.network);
  console.log(
    `Current registry: ${JSON.stringify(
      Array.from(registry.safeOrders.entries())
    )}`
  );

  transactionEvent.logs.forEach((log) => {
    if (log.topics[0] === iface.getEventTopic("Trade")) {
      const t = iface.decodeEventLog("Trade", log.data, log.topics);
      const { owner, orderUid } = t;

      // Check if the owner is in the registry
      if (registry.safeOrders.has(owner)) {
        // Get the conditionalOrders for the owner
        const conditionalOrders = registry.safeOrders.get(owner);
        // Iterate over the conditionalOrders and update the status of the orderUid
        conditionalOrders?.forEach((conditionalOrder) => {
          // Check if the orderUid is in the conditionalOrder
          if (conditionalOrder.orders.has(orderUid)) {
            // Update the status of the orderUid to FILLED
            conditionalOrder.orders.set(orderUid, OrderStatus.FILLED);
          }
        });
      }
    }
  });

  console.log(
    `Updated registry: ${JSON.stringify(
      Array.from(registry.safeOrders.entries())
    )}`
  );
  await registry.write();
};

export const checkForAndPlaceOrder: ActionFn = async (
  context: Context,
  event: Event
) => {
  const blockEvent = event as BlockEvent;
  const registry = await Registry.load(context, blockEvent.network);
  const chainContext = await ChainContext.create(context, blockEvent.network);

  // enumerate all the safeOrders
  for (const [
    safeAddress,
    conditionalOrders,
  ] of registry.safeOrders.entries()) {
    console.log(`Checking ${safeAddress}...`);

    // enumerate all the `ConditionalOrder`s for a given safe
    for (const conditionalOrder of conditionalOrders) {
      console.log(`Checking payload ${conditionalOrder.payload}...`);
      const contract = ConditionalOrder__factory.connect(
        safeAddress,
        chainContext.provider
      );
      try {
        const order: Order = {
          ...(await contract.callStatic.getTradeableOrder(
            conditionalOrder.payload
          )),
          kind: OrderKind.SELL,
          sellTokenBalance: OrderBalance.ERC20,
          buyTokenBalance: OrderBalance.ERC20,
        };

        // calculate the orderUid
        const orderUid = computeOrderUid(
          {
            name: "Gnosis Protocol",
            version: "v2",
            chainId: blockEvent.network,
            verifyingContract: "0x9008D19f58AAbD9eD0D60971565AA8510560ab41",
          },
          {
            ...order,
            receiver:
              order.receiver === ethers.constants.AddressZero
                ? undefined
                : order.receiver,
          },
          safeAddress
        );

        // if the orderUid has not been submitted, or filled, then place the order
        if (!conditionalOrder.orders.has(orderUid)) {
          console.log(
            `Placing orderuid ${orderUid} with Order: ${JSON.stringify(order)}`
          );

          await placeOrder(
            { ...order, from: safeAddress, payload: conditionalOrder.payload },
            chainContext.api_url
          );

          conditionalOrder.orders.set(orderUid, OrderStatus.SUBMITTED);
        } else {
          console.log(
            `OrderUid ${orderUid} status: ${conditionalOrder.orders.get(
              orderUid
            )}`
          );
        }
      } catch (e: any) {
        if (e.code === Logger.errors.CALL_EXCEPTION) {
          switch (e.errorName) {
            case "OrderNotValid":
              // The conditional order has not expired, or been cancelled, but the order is not valid
              // For example, with TWAPs, this may be after `span` seconds have passed in the epoch.
              continue;
            case "OrderExpired":
              console.log(
                `Conditional order on safe ${safeAddress} expired. Unfilled orders:`
              );
              printUnfilledOrders(conditionalOrder.orders);
              console.log("Removing conditional order from registry");
              conditionalOrders.delete(conditionalOrder);
              continue;
            case "OrderCancelled":
              console.log(
                `Conditional order on safe ${safeAddress} cancelled. Unfilled orders:`
              );
              printUnfilledOrders(conditionalOrder.orders);
              console.log("Removing conditional order from registry");
              conditionalOrders.delete(conditionalOrder);
              continue;
          }
        }

        console.log(`Not tradeable (${e})`);
      }
    }
  }

  // Update the registry
  await registry.write();
};

// Print a list of all the orders that were placed and not filled
export const printUnfilledOrders = (orders: Map<string, OrderStatus>) => {
  console.log("Unfilled orders:");
  for (const [orderUid, status] of orders.entries()) {
    if (status === OrderStatus.SUBMITTED) {
      console.log(orderUid);
    }
  }
};

async function placeOrder(order: any, api_url: string) {
  try {
    const { data } = await axios.post(
      `${api_url}/api/v1/orders`,
      {
        sellToken: order.sellToken,
        buyToken: order.buyToken,
        receiver: order.receiver,
        sellAmount: order.sellAmount.toString(),
        buyAmount: order.buyAmount.toString(),
        validTo: order.validTo,
        appData: order.appData,
        feeAmount: order.feeAmount.toString(),
        kind: "sell",
        partiallyFillable: order.partiallyFillable,
        signature: order.payload,
        signingScheme: "eip1271",
        from: order.from,
      },
      {
        headers: {
          "Content-Type": "application/json",
          accept: "application/json",
        },
      }
    );
    console.log(`API response: ${data}`);
  } catch (error: any) {
    if (error.response) {
      // The request was made and the server responded with a status code
      // that falls out of the range of 2xx
      console.log(error.response.status);
      console.log(error.response.data);
    } else if (error.request) {
      // The request was made but no response was received
      // `error.request` is an instance of XMLHttpRequest in the browser and an instance of
      // http.ClientRequest in node.js
      console.log(error.request);
    } else if (error.message) {
      // Something happened in setting up the request that triggered an Error
      console.log("Error", error.message);
    } else {
      console.log(error);
    }
    throw error;
  }
}

class ChainContext {
  provider: ethers.providers.Provider;
  api_url: string;

  constructor(provider: ethers.providers.Provider, api_url: string) {
    this.provider = provider;
    this.api_url = api_url;
  }

  public static async create(
    context: Context,
    network: string
  ): Promise<ChainContext> {
    const node_url = await context.secrets.get(`NODE_URL_${network}`);
    const provider = new ethers.providers.JsonRpcProvider(node_url);
    return new ChainContext(provider, apiUrl(network));
  }
}

function apiUrl(network: string): string {
  switch (network) {
    case "1":
      return "https://api.cow.fi/mainnet";
    case "5":
      return "https://api.cow.fi/goerli";
    case "100":
      return "https://api.cow.fi/xdai";
    default:
      throw "Unsupported network";
  }
}
