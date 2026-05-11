export async function forEachConcurrent<T>(items: T[], limit: number, mapper: (item: T, index: number) => Promise<void>): Promise<void> {
  let next = 0;
  const workers = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (next < items.length) {
      const index = next;
      next += 1;
      await mapper(items[index], index);
    }
  });
  await Promise.all(workers);
}
