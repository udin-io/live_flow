/**
 * LiveFlow - Main Phoenix LiveView Hook, with ELK auto-layout.
 *
 * Import `LiveFlowHook` from "live_flow/core" instead when the page never
 * asks for auto-layout: that build leaves out the ELK engine.
 */

import { LiveFlowHookCore } from './flow_hook_core.js';
import { getLayoutedElements } from '../utils/layout.js';

export const LiveFlowHook = { ...LiveFlowHookCore, layoutEngine: getLayoutedElements };
