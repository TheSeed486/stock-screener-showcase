mod common;
use common::*;
use kline_engine::provider::ParquetDataProvider;

#[test]
fn count_a_shares() {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }
    let symbols = load_available_symbols(&provider);
    println!("A股总数: {}", symbols.len());
    // 按市场分组
    let sz: Vec<_> = symbols.iter().filter(|(m,_,_)| *m==0).collect();
    let sh: Vec<_> = symbols.iter().filter(|(m,_,_)| *m==1).collect();
    let bj: Vec<_> = symbols.iter().filter(|(m,_,_)| *m==2).collect();
    println!("  深市: {}  沪市: {}  北证: {}", sz.len(), sh.len(), bj.len());
    assert_eq!(symbols.len(), 5525, "应为 5525 只 A 股");
}
