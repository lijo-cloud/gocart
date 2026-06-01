/** @type {import('next').NextConfig} */
const nextConfig = {
    images:{
        unoptimized: true
    },
    output: 'standalone',
    generateBuildId: async () => {
    return process.env.GIT_COMMIT || Date.now().toString();
  }
};

export default nextConfig;
