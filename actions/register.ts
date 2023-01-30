import {
  ActionFn,
  Context,
  Event,
  TransactionEvent,
  Storage,
} from "@tenderly/actions";
import { BytesLike } from "ethers";

import { ConditionalOrder__factory } from "./types";

export const addContract: ActionFn = async (context: Context, event: Event) => {
  const transactionEvent = event as TransactionEvent;
  const iface = ConditionalOrder__factory.createInterface();

  const registry = await Registry.load(context, transactionEvent.network);
  console.log(
    `Current registry: ${JSON.stringify(
      Array.from(registry.safeOrders.entries())
    )}`
  );

  transactionEvent.logs.forEach((log) => {
    if (log.topics[0] === iface.getEventTopic("ConditionalOrderCreated")) {
      const [safeAddress, payload] = iface.decodeEventLog(
        "ConditionalOrderCreated",
        log.data,
        log.topics
      );

      // There are two problems here:
      // 1. The safe may already be in the registry, but the payload may not be.
      // 2. The safe may not be in the registry at all.

      if (registry.safeOrders.has(safeAddress)) {
        const conditionalOrders = registry.safeOrders.get(safeAddress);
        console.log(
          `adding payload ${payload} to already existing contract ${safeAddress}`
        );
        if (!conditionalOrders?.has(payload))
          conditionalOrders?.add({ payload, orders: new Map() });
      } else {
        console.log(`adding payload ${payload} to new contract ${safeAddress}`);
        registry.safeOrders.set(
          safeAddress,
          new Set([{ payload, orders: new Map() }])
        );
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

export const storageKey = (network: string): string => {
  return `CONDITIONAL_ORDER_REGISTRY_${network}`;
};

export enum OrderStatus {
  SUBMITTED = 1,
  FILLED = 2,
}

export type ConditionalOrder = {
  payload: BytesLike;
  orders: Map<string, OrderStatus>;
};

export class Registry {
  safeOrders: Map<string, Set<ConditionalOrder>>;
  storage: Storage;
  network: string;

  constructor(
    safeOrders: Map<string, Set<ConditionalOrder>>,
    storage: Storage,
    network: string
  ) {
    this.safeOrders = safeOrders;
    this.storage = storage;
    this.network = network;
  }

  public static async load(
    context: Context,
    network: string
  ): Promise<Registry> {
    const str = await context.storage.getStr(storageKey(network));
    if (str === null || str === undefined || str === "") {
      return new Registry(
        new Map<string, Set<ConditionalOrder>>(),
        context.storage,
        network
      );
    }

    const safeOrders = JSON.parse(str, reviver);
    return new Registry(safeOrders, context.storage, network);
  }

  public async write() {
    await this.storage.putStr(
      storageKey(this.network),
      JSON.stringify(this.safeOrders, replacer)
    );
  }
}

// Utilities for serializing and deserializing Maps and Sets

export function replacer(_key: any, value: any) {
  if (value instanceof Map) {
    return {
      dataType: "Map",
      value: Array.from(value.entries()),
    };
  } else if (value instanceof Set) {
    return {
      dataType: "Set",
      value: Array.from(value.values()),
    };
  } else {
    return value;
  }
}

export function reviver(_key: any, value: any) {
  if (typeof value === "object" && value !== null) {
    if (value.dataType === "Map") {
      return new Map(value.value);
    } else if (value.dataType === "Set") {
      return new Set(value.value);
    }
  }
  return value;
}
