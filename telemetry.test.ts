// Tests unitaires de la logique du dashboard (lib/telemetry.ts).
// Lancement : pnpm test   (utilise le lanceur de tests intégré à Node 22, aucune dépendance)
import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  computeAnomalyScore,
  ingest,
  ingestVision,
  isValidDetections,
  isValidPayload,
  onCritical,
  type CriticalEvent,
  type Reading,
} from '../lib/telemetry.ts'

const reading = (temperature: number, gas: number): Reading => ({
  ts: 0, temperature, humidity: 45, gas, presence: false, distance: null, anomalyScore: 0,
})

test('accepte une mesure valide du capteur', () => {
  assert.equal(isValidPayload({ temperature: 24.5, humidity: 52, gas: 120, presence: false }), true)
})

test('rejette les mesures impossibles ou mal formées', () => {
  assert.equal(isValidPayload({ temperature: 500, gas: 10, presence: false }), false) // trop chaud pour un DHT22
  assert.equal(isValidPayload({ temperature: 24, gas: -5, presence: false }), false)
  assert.equal(isValidPayload({ temperature: 24, gas: 10, presence: 'oui' }), false)
  assert.equal(isValidPayload(null), false)
})

test('valide le format des détections de la caméra', () => {
  const ok = [{ label: 'person', confidence: 0.9, box: { x: 0.1, y: 0.1, w: 0.2, h: 0.4 } }]
  assert.equal(isValidDetections(ok), true)
  assert.equal(isValidDetections([{ label: 'person', confidence: 3, box: { x: 0, y: 0, w: 1, h: 1 } }]), false)
})

test("le score d'anomalie reste bas quand les mesures sont stables", () => {
  const history = Array.from({ length: 20 }, () => reading(23, 20))
  assert.ok(computeAnomalyScore(history, 23, 20) < 0.3)
})

test("le score d'anomalie monte lors d'un pic de gaz", () => {
  const history = Array.from({ length: 20 }, () => reading(23, 20))
  assert.ok(computeAnomalyScore(history, 23, 600) >= 0.7)
})

test('un gaz au-dessus du seuil déclenche une alerte critique (buzzer)', () => {
  const events: CriticalEvent[] = []
  const off = onCritical((e) => events.push(e))
  ingest({ nodeId: 'pyramide-test', temperature: 23, gas: 5000, presence: false })
  off()
  assert.ok(events.length >= 1)
  assert.match(events[0].reason, /Gaz/)
})

test('caméra (personne) + PIR = intrusion confirmée', () => {
  const events: CriticalEvent[] = []
  const off = onCritical((e) => events.push(e))
  ingest({ nodeId: 'pyramide-test', temperature: 23, gas: 10, presence: true })
  ingestVision([{ label: 'person', confidence: 0.9, box: { x: 0.5, y: 0.3, w: 0.2, h: 0.5 } }])
  off()
  assert.ok(events.some((e) => /Intrusion/.test(e.reason)))
})
