import { getPreferenceValues, LocalStorage } from "@raycast/api";
import { BridgeClient } from "../bridge.ts";
import { ContactBook } from "./contactBook.ts";
import { ContactService } from "./contactService.ts";

export interface Preferences { cliPath: string; credentialPath?: string; appPath?: string; backupPath?: string }
export function preferences(): Preferences & { appPath: string } {
  const values = getPreferenceValues<Preferences>(); return { ...values, appPath: values.appPath || "/Applications/WeChat.app" };
}
export function createBridge(): BridgeClient { return new BridgeClient(preferences().credentialPath); }
export function createContactService(): ContactService { return new ContactService(createBridge()); }
export const storageService = new ContactBook({ get: (key) => LocalStorage.getItem<string>(key), set: (key, value) => LocalStorage.setItem(key, value) });
