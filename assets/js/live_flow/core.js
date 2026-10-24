/**
 * LiveFlow - Phoenix LiveView Flow Library
 *
 * The same exports as index.js, with a hook that leaves out the ELK
 * auto-layout engine. Import from "live_flow/core".
 */

import { LiveFlowHookCore as LiveFlowHook } from './hooks/flow_hook_core.js';

export { LiveFlowHook };

// Export utility hooks for file import/export
export { FileImportHook, setupDownloadHandler } from './hooks/utility_hooks.js';

// Export individual managers for advanced usage
export { CoordinateUtils } from './utils/coordinates.js';
export { PanZoomManager } from './interaction/pan_zoom.js';
export { NodeDragManager } from './interaction/node_drag.js';
export { ConnectionManager } from './interaction/connection.js';
export { SelectionManager } from './interaction/selection.js';

// Default export for convenience
export default {
  LiveFlow: LiveFlowHook
};
