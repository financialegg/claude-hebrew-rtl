export type SmartRtlEnabled = boolean

declare module 'claude-code' {
  interface PluginState {
    'smart-rtl-he': { isEnabled: SmartRtlEnabled }
  }
}
