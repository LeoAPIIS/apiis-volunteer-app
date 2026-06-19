import { createClient } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error(
    '缺少 Supabase 环境变量。请复制 .env.example 为 .env.local，并填入 VITE_SUPABASE_URL 与 VITE_SUPABASE_ANON_KEY。',
  )
}

export const supabase = createClient(supabaseUrl, supabaseAnonKey)
