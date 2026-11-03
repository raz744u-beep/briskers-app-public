"""Read-only monetary rounding preflight for a captured local invoice.

No customer data, server writes, or payment posting. Example synthetic
amounts match the observed calculation pattern, not private identifiers.
"""
from decimal import Decimal, ROUND_HALF_UP

RATE = Decimal("0.0975")
SAMPLE = [
    ("2", "1681.98"), ("3.6", "150"), ("1", "495"),
    ("1", "51.67"), ("1", "225.32"), ("2", "4.89"),
    ("1", "123.32"), ("7", "1.58"), ("10", "150"),
    ("2", "38"), ("1", "385.66"), ("1", "160.32"),
    ("1", "18.45"), ("1", "26"), ("1", "150"),
    ("2", "4.98"), ("1", "7.38"), ("1", "28"),
]

def cents(n):
    return n.quantize(Decimal(".01"), rounding=ROUND_HALF_UP)

def preview(lines, rate=RATE):
    bases = [Decimal(qty) * Decimal(price) for qty, price in lines]
    net = sum(bases)
    local_tax_raw = net * rate
    server_tax_per_line = sum(cents(cents(base) * rate) for base in bases)
    return {
        "net": cents(net),
        "local_tax": cents(local_tax_raw),
        "server_tax": server_tax_per_line,
        "local_total": cents(net + local_tax_raw),
        "server_total": cents(net + server_tax_per_line),
    }

if __name__ == "__main__":
    value = preview(SAMPLE)
    assert len(SAMPLE) == 18
    assert value == {
        "net": Decimal("7181.88"),
        "local_tax": Decimal("700.23"),
        "server_tax": Decimal("700.24"),
        "local_total": Decimal("7882.11"),
        "server_total": Decimal("7882.12"),
    }, value
    print("PASS: recovered invoice rounding mismatch confirmed (+$0.01); no writes")
