#include "../Source/SkyIslands/Core/IslandField.h"
#include <cassert>
#include <iostream>
#include <limits>
#include <map>
#include <tuple>
int main(){
    using namespace SkyTerrain;
    Field field(41,2400);
    assert(field.Density({0,0,-400})>0);
    assert(field.Density({0,0,500})<0);
    assert(field.Density({4000,0,-400})<0);
    assert(field.Material({0,0,field.Top(0,0)-50})==0);
    assert(field.Material({0,0,field.Top(0,0)-200})==2);
    assert(field.Material({0,0,field.Top(0,0)-400})==1);
    Stamp cavity{{0,0,-450},200};
    const auto before=field.Density(cavity.center);
    const double removed=field.Excavate(cavity);
    assert(before>0&&removed>0&&field.Density(cavity.center)<0);
    const auto stamps=field.stamps.size();
    assert(field.Excavate(cavity)==0&&field.stamps.size()==stamps);
    assert(field.Excavate({{5000,0,0},200})==0);
    assert(field.Excavate({{0,0,0},-1})==0);
    assert(field.Excavate({{std::numeric_limits<double>::quiet_NaN(),0,0},200})==0);
    assert(field.Excavate({{0,0,0},std::numeric_limits<double>::infinity()})==0);
    assert(field.stamps.size()==stamps);
    // A true enclosed cavity has an inward-facing surface, not a heightfield hole.
    auto mesh=field.Mesh(200);
    assert(!mesh.empty()&&mesh.size()<200000);
    int innerTriangles=0;
    using Key=std::tuple<long long,long long,long long>;
    std::map<std::pair<Key,Key>,int> edgeCounts;
    auto key=[](Vec3 p){return Key{std::llround(p.x*1000),std::llround(p.y*1000),std::llround(p.z*1000)};};
    for(const auto& triangle:mesh){
        const auto& a=triangle.vertices[0];const auto& b=triangle.vertices[1];const auto& c=triangle.vertices[2];
        assert(Finite(a.position)&&Finite(b.position)&&Finite(c.position));
        assert(Finite(a.normal)&&std::abs(Length(a.normal)-1)<.00001);
        Vec3 center=(a.position+b.position+c.position)*(1.0/3);
        assert(Dot(Cross(b.position-a.position,c.position-a.position),field.Normal(center))>=-1e-5);
        for(int e=0;e<3;++e){Key ka=key(triangle.vertices[e].position),kb=key(triangle.vertices[(e+1)%3].position);if(kb<ka)std::swap(ka,kb);++edgeCounts[{ka,kb}];}
        if(Length(center-cavity.center)<230) {++innerTriangles;assert(Dot(a.normal,a.position-cavity.center)<0);}
    }
    assert(innerTriangles>0);
    for(const auto& edge:edgeCounts)assert(edge.second==2); // Closed outer shell and cave.
    Field restored(field.seed,field.radius);restored.stamps=field.stamps;
    for(int i=0;i<100;++i){Vec3 p{double(i*37-1800),double(i*19-900),double(-i*11)};assert(field.Density(p)==restored.Density(p));}
    Field bounded(41,2400);bounded.stamps.resize(Field::MaxStamps,{{600,0,-100},100});
    assert(bounded.Excavate({{-1000,0,-300},100})==0);
    auto a=Field(41,2400).Mesh(400),b=Field(41,2400).Mesh(400);
    assert(a.size()==b.size());
    for(std::size_t i=0;i<a.size();++i)assert(a[i].vertices[0].position.x==b[i].vertices[0].position.x);
    std::cout<<"TERRAIN PASS: "<<mesh.size()<<" triangles, "<<innerTriangles<<" cavity triangles, removed "<<removed<<" cm3\n";
}
