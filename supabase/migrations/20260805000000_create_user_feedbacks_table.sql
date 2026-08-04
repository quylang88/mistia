-- Migration: Create user_feedbacks table
CREATE TABLE IF NOT EXISTS public.user_feedbacks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    category TEXT NOT NULL CHECK (category IN ('bug', 'feature', 'general')),
    rating INT CHECK (rating >= 1 AND rating <= 5),
    content TEXT NOT NULL,
    device_info JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- FK Index for performance & RLS lookup
CREATE INDEX IF NOT EXISTS user_feedbacks_user_id_idx ON public.user_feedbacks(user_id);

-- Enable RLS
ALTER TABLE public.user_feedbacks ENABLE ROW LEVEL SECURITY;

-- Grants for Supabase API Roles
GRANT SELECT, INSERT ON TABLE public.user_feedbacks TO authenticated, anon;
GRANT ALL ON TABLE public.user_feedbacks TO service_role;

-- RLS Policies
CREATE POLICY "Users can insert feedback" ON public.user_feedbacks
    FOR INSERT WITH CHECK ((SELECT auth.uid()) = user_id OR user_id IS NULL);

CREATE POLICY "Users can view own feedback" ON public.user_feedbacks
    FOR SELECT USING ((SELECT auth.uid()) = user_id);

-- Notify PostgREST schema cache reload
NOTIFY pgrst, 'reload schema';
