# Be sure to restart your server when you modify this file.

# Your secret key for verifying cookie session data integrity.
# If you change this key, all old sessions will become invalid!
# Make sure the secret is at least 30 characters and all random, 
# no regular words or you'll be exposed to dictionary attacks.
ActionController::Base.session = {
  :key         => '_foo_session',
  :secret      => '544c0ee719be743a9c1f0b602bb4198a550048c0c36432434b1017aeeda5af0fb8f3c44dc2810c6396eff23ef0b6072f6d5a1f190d2b9be99cfad3b36d787a80'
}

# Use the database for sessions instead of the cookie-based default,
# which shouldn't be used to store highly confidential information
# (create the session table with "rake db:sessions:create")
# ActionController::Base.session_store = :active_record_store
