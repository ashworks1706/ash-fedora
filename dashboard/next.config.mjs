/** Static export: `npm run build` writes out/, served by `tailscale serve`. */
const nextConfig = {
  output: "export",
  images: { unoptimized: true },
  reactStrictMode: true,
};
export default nextConfig;
