data "aws_route53_zone" "delegated_zone" {
  provider = aws.dns
  name     = local.hosted_zone_name
}

output "zoneid" {
  value = data.aws_route53_zone.delegated_zone.zone_id
}

output "userid" {
  value = data.aws_caller_identity.current_account.user_id
}

resource "aws_route53_record" "node" {
  provider = aws.dns
  for_each = aws_instance.nodes
  name     = "node${each.key}.${local.base_domain}"
  type     = "CNAME"
  ttl      = 60
  zone_id  = data.aws_route53_zone.delegated_zone.id

  records = [each.value.public_dns]
}

resource "aws_dynamodb_table_item" "dns_records" {
  count      = var.persist_dns_records_to_dynamo ? 1 : 0
  provider   = aws.dns
  depends_on = [aws_route53_record.node]
  hash_key   = "user_id"
  item       = jsonencode(
    {
      "user_id" : { "S" : split(":", data.aws_caller_identity.current_account.user_id)[0] },
      "display_name" : { "S" : data.aws_canonical_user_id.current_user.display_name },
      "records" : { "SS" : [for record in aws_route53_record.node : record.fqdn] }
    })
  table_name = "k8s-kurs-group-management-dashboard"
}