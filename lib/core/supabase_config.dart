import 'package:supabase_flutter/supabase_flutter.dart';

const supabaseUrl = 'https://coensavcnuwuqaeszohb.supabase.co';
const supabasePublishableKey = 'sb_publishable_tY4v9OoY0nkbeFl-5cnGbA_FoWzD9aP';

SupabaseClient get supabase => Supabase.instance.client;
