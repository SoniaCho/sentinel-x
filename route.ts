// Route de santé : utilisée par le smoke test CI et la vérification après déploiement.
export const dynamic = 'force-dynamic'

export function GET() {
  return Response.json({ status: 'ok' }, { headers: { 'Cache-Control': 'no-store' } })
}
