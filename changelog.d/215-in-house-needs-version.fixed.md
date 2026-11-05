- A package from your own registry whose versions could not be read, or
  that has no version, no longer counts as an in-house package that is up to
  date. It now keeps the latest version from the previous check, or gets the
  public lookup and vulnerability check like any other package. A name that
  only your own registry knows is still never sent anywhere: it shows "Not
  checked" with the reason that the registry gave no latest version.
