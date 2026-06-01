/** @type {import('next').NextConfig} */
const nextConfig = {
    images:{
        unoptimized: true
    },
    output: 'standalone',
    generateEtags: false,
  webpack: (config) => {
    config.output.filename = 'static/chunks/[name].[contenthash].js';
    return config;
  }
};

export default nextConfig;
