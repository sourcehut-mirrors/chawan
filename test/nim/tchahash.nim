import utils/chahash

proc main() =
  assert chibihash64("", 55555) == 0x58AEE94CA9FB5092'u64
  assert chibihash64("", 0) == 0xD4F69E3ECCF128FC'u64
  assert chibihash64("hi", 0) == 0x92C85CA994367DAC'u64
  assert chibihash64("123", 0) == 0x788A224711FF6E25'u64
  assert chibihash64("abcdefgh", 0) == 0xA2E39BE0A0689B32'u64
  assert chibihash64("Hello, world!", 0) == 0xABF8EB3100B2FEC7'u64
  assert chibihash64("qwertyuiopasdfghjklzxcvbnm123456", 0) == 0x90FC5DB7F56967FA'u64
  assert chibihash64("qwertyuiopasdfghjklzxcvbnm123456789", 0) == 0x6DCDCE02882A4975'u64

main()
