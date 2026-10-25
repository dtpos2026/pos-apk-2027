import { describe, expect, it } from 'vitest';
import { pinElement } from './PhonesMap';
import type { Device } from './api';

const device = { id: 'a__b', uid: 'a', phoneId: 'b', model: 'Galaxy', android: '14', appVersion: '1', lastSeenAt: new Date(), locationAllowed: true, lat: 1, lng: 2 } as Device;

describe('map pin', () => {
  it('shows the restaurant logo in a round badge with its name', () => {
    const el = pinElement({ device, restaurant: 'Takeaway Pizza', online: true, logo: 'data:image/png;base64,AAAA' });
    expect(el.querySelector('.pin-head img')?.getAttribute('src')).toBe('data:image/png;base64,AAAA');
    expect(el.querySelector('.pin-name')?.textContent).toBe('Takeaway Pizza');
  });
  it('falls back to the first letter, in the offline red', () => {
    const el = pinElement({ device, restaurant: 'burger point', online: false });
    expect(el.querySelector('.pin-head')?.textContent).toBe('B');
    expect((el.querySelector('.pin-head') as HTMLElement).style.borderColor).toMatch(/196, 20, 20|#c41414/i);
  });
  it('never turns a name or a strange logo into HTML', () => {
    const el = pinElement({ device, restaurant: '<img src=x onerror=alert(1)>', online: true, logo: 'javascript:alert(1)' });
    expect(el.querySelector('.pin-name')?.textContent).toBe('<img src=x onerror=alert(1)>');
    expect(el.querySelectorAll('img').length).toBe(0);
  });
});
