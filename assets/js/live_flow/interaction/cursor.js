/**
 * CursorManager - Built-in remote cursor rendering for LiveFlow
 *
 * Handles rendering remote user cursors within the flow container,
 * broadcasting local cursor position, and repositioning cursors
 * when the viewport changes. Uses lerp interpolation for smooth
 * remote cursor movement.
 */
// Other users' pages draw this color, so only plain color values pass.
const COLOR = /^(?:#[0-9a-fA-F]{3,8}|[a-zA-Z]{3,20}|(?:rgb|rgba|hsl|hsla)\([0-9.,%\s/]{1,60}\))$/;
const DEFAULT_COLOR = '#3b82f6';

function safeColor(color) {
  return typeof color === 'string' && COLOR.test(color) ? color : DEFAULT_COLOR;
}

export class CursorManager {
  constructor(hook) {
    this.hook = hook;
    this.cursors = {};
    this.lastCursorPush = 0;
    this.throttleMs = 50;
    this._animating = false;

    this.overlayEl = hook.container.querySelector('.lf-cursor-overlay');
  }

  /**
   * Handle local mouse movement — broadcast cursor position in flow-space.
   * Throttled to avoid flooding the server.
   */
  handleMouseMove(event) {
    const now = Date.now();
    if (now - this.lastCursorPush < this.throttleMs) return;
    this.lastCursorPush = now;

    const vp = this.hook.viewport;
    const rect = this.hook.getContainerRect();
    const screenX = event.clientX - rect.left;
    const screenY = event.clientY - rect.top;

    const flowX = (screenX - vp.x) / vp.zoom;
    const flowY = (screenY - vp.y) / vp.zoom;

    this.hook.pushEvent('lf:cursor_move', { x: flowX, y: flowY });
  }

  /**
   * Update or create a remote cursor element.
   * Sets target position for smooth lerp interpolation.
   */
  updateCursor(userId, flowX, flowY, color, name) {
    let cursor = this.cursors[userId];
    if (!cursor) {
      cursor = this.createCursorElement(userId, color, name);
      this.cursors[userId] = cursor;
      // Initialize at target position (no lerp on first appearance)
      cursor.flowX = flowX;
      cursor.flowY = flowY;
    }
    cursor.targetX = flowX;
    cursor.targetY = flowY;
    this._startAnimation();
  }

  /**
   * Remove a remote cursor (user left).
   */
  removeCursor(userId) {
    const cursor = this.cursors[userId];
    if (cursor) {
      cursor.element.remove();
      delete this.cursors[userId];
    }
  }

  /**
   * Reposition all cursors after a viewport change.
   */
  repositionAll() {
    for (const cursor of Object.values(this.cursors)) {
      this.positionCursor(cursor);
    }
  }

  /**
   * Clean up all cursor elements and listeners.
   */
  destroy() {
    this._animating = false;
    for (const cursor of Object.values(this.cursors)) {
      cursor.element.remove();
    }
    this.cursors = {};
  }

  // Private

  _startAnimation() {
    if (this._animating) return;
    this._animating = true;
    this._animate();
  }

  _animate() {
    if (!this._animating) return;

    let needsMore = false;
    for (const cursor of Object.values(this.cursors)) {
      if (cursor.targetX === undefined) continue;
      const dx = cursor.targetX - cursor.flowX;
      const dy = cursor.targetY - cursor.flowY;
      if (Math.abs(dx) > 0.5 || Math.abs(dy) > 0.5) {
        cursor.flowX += dx * 0.35;
        cursor.flowY += dy * 0.35;
        needsMore = true;
      } else {
        cursor.flowX = cursor.targetX;
        cursor.flowY = cursor.targetY;
      }
      this.positionCursor(cursor);
    }

    if (needsMore) {
      requestAnimationFrame(() => this._animate());
    } else {
      this._animating = false;
    }
  }

  createCursorElement(userId, color, name) {
    color = safeColor(color);
    const el = document.createElement('div');
    el.className = 'lf-remote-cursor';
    el.dataset.userId = userId;

    // The name and color come from other users, so they are set as text and
    // attribute values, never parsed as markup.
    const svgNS = 'http://www.w3.org/2000/svg';
    const svg = document.createElementNS(svgNS, 'svg');
    svg.setAttribute('width', '16');
    svg.setAttribute('height', '20');
    svg.setAttribute('viewBox', '0 0 16 20');
    svg.setAttribute('fill', 'none');

    const path = document.createElementNS(svgNS, 'path');
    path.setAttribute('d', 'M0 0L16 12L8 12L6 20L0 0Z');
    path.setAttribute('fill', String(color));
    path.setAttribute('stroke', 'white');
    path.setAttribute('stroke-width', '1');
    svg.appendChild(path);

    const label = document.createElement('span');
    label.className = 'lf-remote-cursor-label';
    label.style.background = String(color);
    label.textContent = String(name);

    el.append(svg, label);

    if (this.overlayEl) {
      this.overlayEl.appendChild(el);
    }

    return { element: el, flowX: 0, flowY: 0, targetX: undefined, targetY: undefined, color, name };
  }

  positionCursor(cursor) {
    const vp = this.hook.viewport;
    const screenX = cursor.flowX * vp.zoom + vp.x;
    const screenY = cursor.flowY * vp.zoom + vp.y;
    cursor.element.style.transform = 'translate(' + screenX + 'px, ' + screenY + 'px)';
  }
}
