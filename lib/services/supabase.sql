-- =====================================================
-- SUPABASE SCHEMA FOR GIS ATTENDANCE SYSTEM
-- Run these queries in your Supabase SQL Editor
-- =====================================================

-- ===================== CREATE OFFICERS TABLE =====================
CREATE TABLE IF NOT EXISTS public.officers (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  officer_id VARCHAR(50) NOT NULL UNIQUE,
  full_name VARCHAR(255) NOT NULL,
  email VARCHAR(255) NOT NULL,
  face_image_path VARCHAR(500) NOT NULL,
  face_image_url TEXT NOT NULL,
  is_active BOOLEAN DEFAULT true,
  department VARCHAR(100),
  position VARCHAR(100),
  phone_number VARCHAR(20),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  last_login TIMESTAMP WITH TIME ZONE
);

-- Create index on officer_id for faster lookups
CREATE INDEX idx_officers_officer_id ON public.officers(officer_id);
CREATE INDEX idx_officers_email ON public.officers(email);
CREATE INDEX idx_officers_is_active ON public.officers(is_active);

-- ===================== CREATE OFFICER_REGISTRATIONS TABLE =====================
CREATE TABLE IF NOT EXISTS public.officer_registrations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  officer_id VARCHAR(50) NOT NULL UNIQUE,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name VARCHAR(255) NOT NULL,
  email VARCHAR(255) NOT NULL,
  face_image_path VARCHAR(500) NOT NULL,
  face_image_url TEXT NOT NULL,
  status VARCHAR(50) DEFAULT 'pending', -- 'pending', 'approved', 'rejected'
  registration_date TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  approved_by UUID REFERENCES auth.users(id),
  approved_at TIMESTAMP WITH TIME ZONE,
  rejection_reason TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes on officer_registrations
CREATE INDEX idx_registrations_officer_id ON public.officer_registrations(officer_id);
CREATE INDEX idx_registrations_status ON public.officer_registrations(status);
CREATE INDEX idx_registrations_email ON public.officer_registrations(email);

-- ===================== CREATE ATTENDANCE TABLE =====================
CREATE TABLE IF NOT EXISTS public.attendance (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  officer_id VARCHAR(50) NOT NULL,
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  attendance_type VARCHAR(20) NOT NULL, -- 'check_in' or 'check_out'
  timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
  date DATE NOT NULL, -- For easy date-based queries
  time_only TIME,
  location VARCHAR(255),
  latitude DECIMAL(10, 8),
  longitude DECIMAL(11, 8),
  notes TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes on attendance
CREATE INDEX idx_attendance_officer_id ON public.attendance(officer_id);
CREATE INDEX idx_attendance_date ON public.attendance(date);
CREATE INDEX idx_attendance_timestamp ON public.attendance(timestamp);
CREATE INDEX idx_attendance_type ON public.attendance(attendance_type);

-- ===================== CREATE ATTENDANCE_SUMMARY TABLE =====================
CREATE TABLE IF NOT EXISTS public.attendance_summary (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  officer_id VARCHAR(50) NOT NULL,
  date DATE NOT NULL UNIQUE,
  check_in_time TIMESTAMP WITH TIME ZONE,
  check_out_time TIMESTAMP WITH TIME ZONE,
  duration_minutes INTEGER,
  status VARCHAR(50), -- 'present', 'absent', 'late', 'early_checkout'
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes on attendance_summary
CREATE INDEX idx_attendance_summary_officer_id ON public.attendance_summary(officer_id);
CREATE INDEX idx_attendance_summary_date ON public.attendance_summary(date);

-- ===================== ENABLE ROW LEVEL SECURITY =====================

-- Enable RLS on officers table
ALTER TABLE public.officers ENABLE ROW LEVEL SECURITY;

-- Policy: Users can only see their own officer record
CREATE POLICY "Officers can view their own record"
ON public.officers
FOR SELECT
USING (auth.uid() = id);

-- Policy: Officers can update their own record (except officer_id)
CREATE POLICY "Officers can update their own record"
ON public.officers
FOR UPDATE
USING (auth.uid() = id)
WITH CHECK (auth.uid() = id);

-- Enable RLS on attendance table
ALTER TABLE public.attendance ENABLE ROW LEVEL SECURITY;

-- Policy: Users can only see their own attendance records
CREATE POLICY "Officers can view their own attendance"
ON public.attendance
FOR SELECT
USING (
  (SELECT id FROM auth.users WHERE id = auth.uid()::uuid) IS NOT NULL AND
  user_id = auth.uid()::uuid
);

-- Policy: Insert attendance records (for check-in/out)
CREATE POLICY "Officers can insert their own attendance"
ON public.attendance
FOR INSERT
WITH CHECK (
  user_id = auth.uid()::uuid
);

-- Enable RLS on attendance_summary table
ALTER TABLE public.attendance_summary ENABLE ROW LEVEL SECURITY;

-- Policy: Users can only see their own summary
CREATE POLICY "Officers can view their own attendance summary"
ON public.attendance_summary
FOR SELECT
USING (
  officer_id IN (
    SELECT officer_id FROM public.officers WHERE id = auth.uid()::uuid
  )
);

-- ===================== CREATE STORAGE BUCKET =====================
-- Run this in Supabase Storage or via the following SQL:

-- Note: Storage buckets are typically created via the UI
-- But you can also use the storage API

-- To create via UI:
-- 1. Go to Supabase Dashboard > Storage
-- 2. Click "New Bucket"
-- 3. Name it: "officer-faces"
-- 4. Make it PRIVATE (not public)
-- 5. Save

-- ===================== STORAGE POLICIES =====================
-- Run these in SQL Editor after creating the bucket

INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES ('officer-faces', 'officer-faces', false, 5242880) -- 5MB limit
ON CONFLICT (id) DO NOTHING;

-- Policy: Officers can upload their own face
CREATE POLICY "Officers can upload their own face"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'officer-faces' AND
  (storage.foldername(name))[1] = 'faces'
);

-- Policy: Officers can view their own face
CREATE POLICY "Officers can view their own face"
ON storage.objects
FOR SELECT
TO authenticated
USING (bucket_id = 'officer-faces');

-- ===================== FUNCTIONS & TRIGGERS =====================

-- Function to update officer last_login
CREATE OR REPLACE FUNCTION update_officer_last_login()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.officers
  SET last_login = NOW()
  WHERE id = NEW.id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to update last_login on attendance insert
CREATE TRIGGER trigger_update_last_login
AFTER INSERT ON public.attendance
FOR EACH ROW
EXECUTE FUNCTION update_officer_last_login();

-- Function to generate attendance summary
CREATE OR REPLACE FUNCTION generate_attendance_summary()
RETURNS TRIGGER AS $$
DECLARE
  check_in_time TIMESTAMP WITH TIME ZONE;
  check_out_time TIMESTAMP WITH TIME ZONE;
  duration INTEGER;
BEGIN
  SELECT timestamp INTO check_in_time
  FROM public.attendance
  WHERE officer_id = NEW.officer_id
    AND date = NEW.date
    AND attendance_type = 'check_in'
  ORDER BY timestamp DESC
  LIMIT 1;

  SELECT timestamp INTO check_out_time
  FROM public.attendance
  WHERE officer_id = NEW.officer_id
    AND date = NEW.date
    AND attendance_type = 'check_out'
  ORDER BY timestamp DESC
  LIMIT 1;

  IF check_in_time IS NOT NULL THEN
    IF check_out_time IS NOT NULL THEN
      duration := EXTRACT(EPOCH FROM (check_out_time - check_in_time))::INTEGER / 60;
    END IF;

    INSERT INTO public.attendance_summary (officer_id, date, check_in_time, check_out_time, duration_minutes, status)
    VALUES (NEW.officer_id, NEW.date, check_in_time, check_out_time, duration, 'present')
    ON CONFLICT (date) DO UPDATE SET
      check_in_time = EXCLUDED.check_in_time,
      check_out_time = EXCLUDED.check_out_time,
      duration_minutes = EXCLUDED.duration_minutes,
      updated_at = NOW();
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for attendance summary
CREATE TRIGGER trigger_attendance_summary
AFTER INSERT ON public.attendance
FOR EACH ROW
EXECUTE FUNCTION generate_attendance_summary();

-- ===================== VIEWS =====================

-- View: Today's attendance
CREATE OR REPLACE VIEW today_attendance AS
SELECT
  o.officer_id,
  o.full_name,
  o.email,
  a.attendance_type,
  a.timestamp,
  a.location
FROM public.officers o
LEFT JOIN public.attendance a ON o.officer_id = a.officer_id AND a.date = CURRENT_DATE
ORDER BY a.timestamp DESC;

-- View: Attendance summary by officer and date range
CREATE OR REPLACE VIEW attendance_report AS
SELECT
  o.officer_id,
  o.full_name,
  o.department,
  s.date,
  s.check_in_time,
  s.check_out_time,
  s.duration_minutes,
  s.status
FROM public.officers o
LEFT JOIN public.attendance_summary s ON o.officer_id = s.officer_id
WHERE s.date >= CURRENT_DATE - INTERVAL '30 days'
ORDER BY o.officer_id, s.date DESC;

-- ===================== NOTES =====================
/*
After running these queries:

1. Update your Flutter pubspec.yaml with Supabase dependencies:
   dependencies:
     supabase_flutter: ^1.10.0
     image_picker: ^0.8.8
     flutter_secure_storage: ^9.0.0

2. Initialize Supabase in your main.dart:
   void main() async {
     WidgetsFlutterBinding.ensureInitialized();
     
     await SupabaseService.initialize(
       url: 'YOUR_SUPABASE_URL',
       anonKey: 'YOUR_SUPABASE_ANON_KEY',
     );
     
     runApp(const MyApp());
   }

3. Update your LoginScreen to use email instead of officer_id:
   - Store email in credentials instead of username
   - Call login(email, password) instead of login(username, password)

4. The face images will be stored in the 'officer-faces' bucket
   - Path format: faces/{officer_id}_{timestamp}.jpg
   - URLs are accessible via the face_image_url field

5. Attendance is automatically tracked with check_in/check_out
   - Daily summaries are auto-generated via database triggers
   - View reports using the attendance_report view
*/