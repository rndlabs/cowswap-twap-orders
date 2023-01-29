import {
  TestTransactionEvent,
  TestLog,
  TestRuntime,
} from "@tenderly/actions-test";
import { strict as assert } from "node:assert";
import { addContract, storageKey } from "../register";

const main = async () => {
  const testRuntime = new TestRuntime();

  // https://goerli.etherscan.io/tx/0xa0f618eea9c1195a7023835bd0306a6ead63fbdb37dd638402e684d0c52220a7#eventlog
  const alreadyIndexedLog = new TestLog();
  alreadyIndexedLog.topics = [
    "0x348a1454f658b360fcb291e66a7adc4a65b64b38b956802a976d5e460d0e2084",
    "0x00000000000000000000000051fcd11117bc85c319fd2848b301bbf6bc2b630f",
  ];

  const newLog = new TestLog();
  newLog.topics = [
    "0x348a1454f658b360fcb291e66a7adc4a65b64b38b956802a976d5e460d0e2084",
    "0x000000000000000000000000EeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
  ];

  const event = new TestTransactionEvent();
  event.logs.push(alreadyIndexedLog);
  event.logs.push(newLog);
  event.network = "mainnet";

  await testRuntime.context.storage.putJson(storageKey(event.network), {
    contracts: ["0x51fCD11117bC85C319FD2848B301BbF6bC2b630f"],
  });

  await testRuntime.execute(addContract, event);

  const storage = await testRuntime.context.storage.getJson(
    storageKey(event.network)
  );
  console.log(storage);
  assert(
    storage.contracts.length == 2,
    "Incorrect amount of contracts indexed"
  );
  assert(
    storage.contracts[0] == "0x51fCD11117bC85C319FD2848B301BbF6bC2b630f",
    "Missing already indexed contract"
  );
  assert(
    storage.contracts[1] == "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
    "Missing new contract"
  );
};

(async () => await main())();
