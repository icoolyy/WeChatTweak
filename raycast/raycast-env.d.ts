/// <reference types="@raycast/api">

/* 🚧 🚧 🚧
 * This file is auto-generated from the extension's manifest.
 * Do not modify manually. Instead, update the `package.json` file.
 * 🚧 🚧 🚧 */

/* eslint-disable @typescript-eslint/ban-types */

type ExtensionPreferences = {
  /** WeChatTweak CLI Path - Absolute path to this branch's dist/wechattweak. Official 2.0.1 lacks the doctor command. */
  "cliPath": string
}

/** Preferences accessible in all the extension's commands */
declare type Preferences = ExtensionPreferences

declare namespace Preferences {
  /** Preferences accessible in the `manage` command */
  export type Manage = ExtensionPreferences & {}
}

declare namespace Arguments {
  /** Arguments passed to the `manage` command */
  export type Manage = {}
}

