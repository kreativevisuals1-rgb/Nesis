/* ============================================================================
   NESIS — shared config
   Loaded by both index.html (parent site) and admin.html (admin panel).
   Fill in SUPABASE_URL and SUPABASE_ANON_KEY before going live — everything
   else here is just a fallback used until the database is connected, or if
   a setting hasn't been saved in Admin → Settings yet.
   ============================================================================ */
window.NESIS_CONFIG = {
  // From Supabase → Project Settings → API
  SUPABASE_URL: 'https://rqyfobofdxzwimlhdrup.supabase.co',        // e.g. 'https://abcxyz.supabase.co'
  SUPABASE_ANON_KEY: 'sb_publishable_L_HswBzdb-mvu6RbPc1GSw_0_OiQ5BP',

  // Fallback WhatsApp Business number (digits only, country code first, no + or spaces).
  // Once Supabase is connected, the real value lives in Admin → Settings and
  // overrides this automatically — you don't need to edit this file again.
  WHATSAPP_NUMBER: '2340000000000',

  // Fallback bank details — same idea, editable later from Admin → Settings.
  BANK: {
    accountName: 'Nesis',
    accountNumber: '0000000000',
    bankName: 'Your Bank Name Here',
  },

  FEE: 50000,
  FEE_DISPLAY: '₦50,000',
  CAPACITY_PER_COURSE: 4,
  TOTAL_SEATS: 20,
  ONBOARDING_DEADLINE: '22 August',

  // Fallback WhatsApp GROUP invite links, shown once a registration is
  // verified. Editable per-course later from Admin → Settings.
  COURSES: {
    'ai-explorer':        { name: 'AI Explorer',        whatsappGroup: 'https://chat.whatsapp.com/REPLACE_AI_EXPLORER' },
    'young-speaker':      { name: 'Young Speaker',       whatsappGroup: 'https://chat.whatsapp.com/REPLACE_YOUNG_SPEAKER' },
    'code-create':        { name: 'Code & Create',       whatsappGroup: 'https://chat.whatsapp.com/REPLACE_CODE_CREATE' },
    'digital-creator':    { name: 'Digital Creator',     whatsappGroup: 'https://chat.whatsapp.com/REPLACE_DIGITAL_CREATOR' },
    'young-entrepreneur': { name: 'Young Entrepreneur',  whatsappGroup: 'https://chat.whatsapp.com/REPLACE_YOUNG_ENTREPRENEUR' },
  },
};
