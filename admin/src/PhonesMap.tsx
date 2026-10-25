import { useEffect, useRef } from 'react';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import type { Device } from './api';
import { ago } from './ui';

export interface MapPoint { device: Device; restaurant: string; online: boolean; logo?: string }

/** A map pin: a round badge with the restaurant's logo (or its first letter), a pointer below, and the name under it. Built with DOM calls only, so names can never inject HTML. */
export function pinElement(p: MapPoint): HTMLElement {
  const color = p.online ? '#1e7b3a' : '#C41414';
  const wrap = document.createElement('div'); wrap.className = 'pin';
  const head = document.createElement('div'); head.className = 'pin-head'; head.style.borderColor = color;
  if (p.logo && p.logo.startsWith('data:image/')) { const img = document.createElement('img'); img.src = p.logo; img.alt = ''; head.appendChild(img); }
  else { head.textContent = (p.restaurant.trim()[0] ?? '?').toUpperCase(); head.style.background = color; head.style.color = '#fff'; }
  const tip = document.createElement('div'); tip.className = 'pin-tip'; tip.style.borderTopColor = color;
  const name = document.createElement('div'); name.className = 'pin-name'; name.textContent = p.restaurant;
  wrap.append(head, tip, name);
  return wrap;
}

/** OpenStreetMap with one marker per phone that shares its location, and a circle showing GPS accuracy. */
export function PhonesMap({ points }: { points: MapPoint[] }) {
  const el = useRef<HTMLDivElement>(null);
  const map = useRef<L.Map | null>(null);
  const layer = useRef<L.LayerGroup | null>(null);

  useEffect(() => {
    if (!el.current || map.current) return;
    map.current = L.map(el.current, { center: [30.3, 70.0], zoom: 5, scrollWheelZoom: false });
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19, attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
    }).addTo(map.current);
    layer.current = L.layerGroup().addTo(map.current);
    return () => { map.current?.remove(); map.current = null; };
  }, []);

  useEffect(() => {
    const m = map.current, g = layer.current;
    if (!m || !g) return;
    g.clearLayers();
    const bounds: L.LatLngTuple[] = [];
    for (const p of points) {
      const { lat, lng, accuracyM } = p.device;
      if (lat == null || lng == null) continue;
      const color = p.online ? '#1e7b3a' : '#C41414';
      L.circle([lat, lng], { radius: Math.max(accuracyM ?? 0, 10), color, weight: 1, fillOpacity: 0.12 }).addTo(g);
      const marker = L.marker([lat, lng], { icon: L.divIcon({ html: pinElement(p), className: 'pin-icon', iconSize: [120, 78], iconAnchor: [60, 50], popupAnchor: [0, -46] }) }).addTo(g);
      const div = document.createElement('div');
      const b = document.createElement('b'); b.textContent = p.restaurant; div.appendChild(b);
      div.appendChild(document.createElement('br'));
      div.appendChild(document.createTextNode(`${p.device.model} · ${p.online ? 'online' : 'offline'} · seen ${ago(p.device.lastSeenAt)}`));
      div.appendChild(document.createElement('br'));
      div.appendChild(document.createTextNode(`location ${ago(p.device.locationAt ?? null)} · ±${Math.round(accuracyM ?? 0)} m`));
      marker.bindPopup(div);
      bounds.push([lat, lng]);
    }
    if (bounds.length === 1) m.setView(bounds[0], 15);
    else if (bounds.length > 1) m.fitBounds(bounds, { padding: [30, 30], maxZoom: 15 });
  }, [points]);

  return <div ref={el} className="map" role="region" aria-label="Map of phones" />;
}
