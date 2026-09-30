export async function isAuthorized(
  req: Request,
  cronSecret: string | undefined,
  getUser: (jwt: string) => Promise<boolean>,
): Promise<boolean> {
  if (cronSecret && req.headers.get("x-cron-secret") === cronSecret) return true;
  const header = req.headers.get("authorization") ?? "";
  const jwt = header.startsWith("Bearer ") ? header.slice("Bearer ".length) : "";
  if (!jwt) return false;
  try {
    return await getUser(jwt);
  } catch {
    return false;
  }
}
