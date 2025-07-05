import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { WagmiProvider } from 'wagmi'
import { config } from '@/lib/wagmi'
import { Toaster } from 'sonner'
import '@/lib/fcl-config' // Import FCL configuration

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 1000 * 60 * 5, // 5 minutes
      refetchOnWindowFocus: false,
    },
  },
})

export default function Providers({ children }: { children: React.ReactNode }) {
  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        {children}
        <Toaster
          position="top-right"
          richColors
          expand={false}
          duration={4000}
          closeButton
        />
      </QueryClientProvider>
    </WagmiProvider>
  )
}