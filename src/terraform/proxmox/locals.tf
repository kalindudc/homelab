locals {
  target_nodes = {
    "collie" = {
      name = "collie"
      ip = "10.0.0.2"
    },
    "terrier" = {
      name = "terrier"
      ip = "10.0.0.2"
    },
    "shepherd" = {
      name = "shepherd"
      ip = "10.0.0.3"
    },
  }

  ssh_key = <<EOF
    ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDliClbKq+DkDrTGtsP/nVj8PnzrQlDWYJ6KeEXp/2qUPZKkaXkaUZ4RGTMGJfKq40TskAta+VkLwGnHrXnJzRVqE5gyOgPA9dlJFEML5Rbz/f72DK8694nQk+/mF1aCirATV72+SKuIEVCH9BiOrtWtHxr4Mc82t9A/rHn4G9xBTwJ6HpWP6mXSb8wvSV56ZZO6vkGJKYEvj98Xc+a/kzIlaP0Hp8cGG1O+sqiakW5CYpUzMmIRkvlPG4eL+NESgzkBnZsVL0yUKYKLF+GffA5bCqG/THPhLsRzTPElBWv7XjDRRZe54ydo1wf2Wkt13JzzMoaw6lLRhY2FggZzM/bUpF29cWUUTX39T+M4dt8Gn9v+ohEogtjRwHbJriRPXbKVYPMcELTgAvDBSNIVMzogmokWq2hUwb304DsWAHXyv7RfeMA737fulsvG301KMdEABhxX2kEVbRggs4i4PMXL+QOiRq8Tgg1ELQ7EhKmX8emrGqLEw3nURMRA7G8yF0= kalindu@malamute.local
  EOF
}
