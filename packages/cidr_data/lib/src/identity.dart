// CIDR Atlas
// OCI natural-identity matching shared by import previews and the store.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'package:cidr_core/cidr_core.dart';

/// Whether two scope values (tenancy or region) can describe the same place:
/// an unknown value on either side does not contradict a known one.
bool sameKnownScope(String first, String second) =>
    first.isEmpty || second.isEmpty || first == second;

/// Whether [existing] is the same observed OCI prefix as [incoming]: the same
/// resource, kind, canonical CIDR and routing domain, in a compatible tenancy.
///
/// The region is not compared. Matching requires the same non-empty resource
/// id, and OCIDs are globally unique, so a region spelled differently, such
/// as `IAD` or `US-ASHBURN-1` stored by v0.3.0 and `us-ashburn-1` from current
/// discovery, still names the same resource. The store then replaces the
/// legacy spelling with the incoming region and keeps the planning fields.
bool sameOciIdentity(PrefixRecord existing, PrefixRecord incoming) =>
    existing.resourceId.isNotEmpty &&
    existing.resourceId == incoming.resourceId &&
    existing.kind == incoming.kind &&
    Cidr.parse(existing.cidr).canonical ==
        Cidr.parse(incoming.cidr).canonical &&
    existing.routingDomain == incoming.routingDomain &&
    sameKnownScope(existing.tenancy, incoming.tenancy);
