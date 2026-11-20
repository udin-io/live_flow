import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { Window } from 'happy-dom';
import { CursorManager } from '../../assets/js/live_flow/interaction/cursor.js';

const window = new Window();
globalThis.document = window.document;
globalThis.requestAnimationFrame = () => 0;

after(() => window.happyDOM.abort());

function setup() {
  const container = document.createElement('div');
  container.innerHTML = '<div class="lf-cursor-overlay"></div>';
  document.body.appendChild(container);

  const hook = {
    container,
    viewport: { x: 0, y: 0, zoom: 1 },
    getContainerRect: () => ({ left: 0, top: 0 }),
    pushEvent: () => {},
  };

  return { overlay: container.querySelector('.lf-cursor-overlay'), manager: new CursorManager(hook) };
}

test('a remote name with markup shows as text and adds no elements', () => {
  const { overlay, manager } = setup();
  const name = '<b id="injected">Alice</b>';

  manager.updateCursor('u1', 10, 20, '#ef4444', name);

  const label = overlay.querySelector('.lf-remote-cursor-label');
  assert.equal(label.textContent, name);
  assert.ok(!overlay.querySelector('#injected'), 'the markup became an element');
});

test('a remote color cannot break out of its attributes', () => {
  const { overlay, manager } = setup();
  const color = '#000"/><b id="injected"></b><path d="';

  manager.updateCursor('u2', 0, 0, color, 'Bob');

  assert.ok(!overlay.querySelector('#injected'), 'the markup became an element');
  assert.equal(overlay.querySelectorAll('path').length, 1);
  assert.equal(overlay.querySelector('.lf-remote-cursor-label').textContent, 'Bob');
});

test('a normal cursor keeps its color and name', () => {
  const { overlay, manager } = setup();

  manager.updateCursor('u3', 0, 0, '#3b82f6', 'Carol');

  assert.equal(overlay.querySelector('path').getAttribute('fill'), '#3b82f6');
  const label = overlay.querySelector('.lf-remote-cursor-label');
  assert.equal(label.textContent, 'Carol');
  assert.match(label.getAttribute('style'), /background:\s*(#3b82f6|rgb\(59, 130, 246\))/);
});

test('a remote color that is not a plain color value falls back to the default', () => {
  const { overlay, manager } = setup();

  manager.updateCursor('u4', 0, 0, 'url(https://example.com/x)', 'Dan');

  assert.equal(overlay.querySelector('path').getAttribute('fill'), '#3b82f6');
});
