#pragma once
// Centimetres throughout. Positive density is solid; no Unreal dependency.
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <limits>
#include <vector>

namespace SkyTerrain {
struct Vec3 {
    double x=0, y=0, z=0;
    Vec3 operator+(Vec3 b) const { return {x+b.x,y+b.y,z+b.z}; }
    Vec3 operator-(Vec3 b) const { return {x-b.x,y-b.y,z-b.z}; }
    Vec3 operator*(double s) const { return {x*s,y*s,z*s}; }
};
inline double Dot(Vec3 a,Vec3 b){return a.x*b.x+a.y*b.y+a.z*b.z;}
inline Vec3 Cross(Vec3 a,Vec3 b){return {a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x};}
inline double Length(Vec3 a){return std::sqrt(Dot(a,a));}
inline Vec3 Unit(Vec3 a){double n=Length(a);return n>1e-10?a*(1/n):Vec3{0,0,1};}
inline bool Finite(Vec3 a){return std::isfinite(a.x)&&std::isfinite(a.y)&&std::isfinite(a.z);}
struct Stamp {Vec3 center; double radius=180;};
struct Vertex {Vec3 position, normal;};
struct Triangle {std::array<Vertex,3> vertices; int material=0;};
class Field {
public:
    static constexpr std::size_t MaxStamps=128;
    std::int32_t seed=41;
    double radius=2400;
    std::vector<Stamp> stamps;
    Field(std::int32_t s=41,double r=2400):seed(s),radius(std::isfinite(r)?std::clamp(r,500.0,6000.0):2400){}
    double Top(double x,double y) const {
        const double a=double(seed%997)*0.137;
        return 42*std::sin(x*.00135+a)*std::cos(y*.00115-a)+19*std::sin((x+y)*.0021+a*.37);
    }
    double BaseDensity(Vec3 p) const {
        if(!Finite(p)) return -std::numeric_limits<double>::infinity();
        double radial=std::hypot(p.x,p.y), theta=std::atan2(p.y,p.x), a=double(seed%997)*.137;
        double limit=radius*(1+.045*std::sin(theta*3+a)+.025*std::sin(theta*7-a));
        double q=radial/limit;
        double bottom=-radius*.75*std::pow(std::max(0.0,1-q*q),.55)-70;
        // Rounded transition at the rim rather than a cubical block boundary.
        double top=Top(p.x,p.y)-p.z, base=p.z-bottom, side=limit-radial;
        return std::min({top,base,side});
    }
    double Density(Vec3 p) const {
        double d=BaseDensity(p);
        for(const auto& s:stamps) d=std::min(d,Length(p-s.center)-s.radius);
        return d;
    }
    Vec3 Normal(Vec3 p) const {
        constexpr double e=1;
        return Unit(Vec3{Density({p.x-e,p.y,p.z})-Density({p.x+e,p.y,p.z}),
                         Density({p.x,p.y-e,p.z})-Density({p.x,p.y+e,p.z}),
                         Density({p.x,p.y,p.z-e})-Density({p.x,p.y,p.z+e})});
    }
    // Simplified geological layers. Tools/material quantities are handled by server gameplay.
    int Material(Vec3 p) const {
        double depth=Top(p.x,p.y)-p.z;
        if(depth<130) return 0; // topsoil
        if(depth<330) return 2; // clay
        const double vein=std::sin(p.x*.008+seed)*std::cos(p.y*.009)+std::sin(p.z*.012);
        return depth>550&&vein>1.25?3:1; // mineral-bearing rock or common stone
    }
    bool ValidStamp(Stamp s) const {
        return Finite(s.center)&&std::isfinite(s.radius)&&s.radius>=80&&s.radius<=260 &&
            std::abs(s.center.x)<=radius*1.2+260&&std::abs(s.center.y)<=radius*1.2+260&&
            s.center.z>=-radius*.9-260&&s.center.z<=500;
    }
    // Deterministic volume quadrature measures newly removed solid only.
    // A duplicate excavation returns zero and does not consume another stamp.
    double RemovedVolume(Stamp s) const {
        if(!ValidStamp(s)||stamps.size()>=MaxStamps) return 0;
        constexpr int n=12;
        const double step=2*s.radius/n;
        std::uint64_t removed=0;
        for(int z=0;z<n;++z)for(int y=0;y<n;++y)for(int x=0;x<n;++x){
            Vec3 p=s.center+Vec3{-s.radius+(x+.5)*step,-s.radius+(y+.5)*step,-s.radius+(z+.5)*step};
            if(Length(p-s.center)<s.radius && Density(p)>1e-6) ++removed;
        }
        return double(removed)*step*step*step;
    }
    double Excavate(Stamp s) {
        const double volume=RemovedVolume(s);
        if(volume>0) stamps.push_back(s);
        return volume;
    }
    std::vector<Triangle> Mesh(double requestedCell=150) const {
        // Bounded full-island rebuild for starter map. Not an unbounded streamed terrain system.
        const double cell=std::max({100.0,requestedCell,radius/19.0});
        Vec3 lo{-radius*1.1-cell,-radius*1.1-cell,-radius*.8-120-cell};
        Vec3 hi{radius*1.1+cell,radius*1.1+cell,150+cell};
        int nx=int(std::ceil((hi.x-lo.x)/cell)),ny=int(std::ceil((hi.y-lo.y)/cell)),nz=int(std::ceil((hi.z-lo.z)/cell));
        std::vector<double> values(std::size_t(nx+1)*(ny+1)*(nz+1));
        auto index=[&](int x,int y,int z){return (std::size_t(z)*(ny+1)+y)*(nx+1)+x;};
        auto point=[&](int x,int y,int z){return lo+Vec3{double(x)*cell,double(y)*cell,double(z)*cell};};
        for(int z=0;z<=nz;++z)for(int y=0;y<=ny;++y)for(int x=0;x<=nx;++x)values[index(x,y,z)]=Density(point(x,y,z));
        constexpr int corners[8][3]={{0,0,0},{1,0,0},{1,1,0},{0,1,0},{0,0,1},{1,0,1},{1,1,1},{0,1,1}};
        constexpr int tets[6][4]={{0,5,1,6},{0,1,2,6},{0,2,3,6},{0,3,7,6},{0,7,4,6},{0,4,5,6}};
        constexpr int edges[6][2]={{0,1},{0,2},{0,3},{1,2},{1,3},{2,3}};
        std::vector<Triangle> out; out.reserve(std::size_t(nx)*ny*10);
        for(int z=0;z<nz;++z)for(int y=0;y<ny;++y)for(int x=0;x<nx;++x){
            Vec3 p[8];double d[8];bool positive=false,negative=false;
            for(int k=0;k<8;++k){int xx=x+corners[k][0],yy=y+corners[k][1],zz=z+corners[k][2];p[k]=point(xx,yy,zz);d[k]=values[index(xx,yy,zz)];positive|=d[k]>0;negative|=d[k]<=0;}
            if(!positive||!negative)continue;
            for(const auto& tet:tets){
                std::array<Vec3,4> cut{};int count=0;
                for(const auto& edge:edges){int ia=tet[edge[0]],ib=tet[edge[1]];if((d[ia]>0)==(d[ib]>0))continue;
                    double t=d[ia]/(d[ia]-d[ib]);cut[count++]=p[ia]+(p[ib]-p[ia])*t;
                }
                if(count<3)continue;
                Vec3 center{};for(int i=0;i<count;++i)center=center+cut[i];center=center*(1.0/count);
                Vec3 normal=Normal(center),u=Unit(cut[0]-center),v=Cross(normal,u);
                std::sort(cut.begin(),cut.begin()+count,[&](Vec3 a,Vec3 b){a=a-center;b=b-center;return std::atan2(Dot(a,v),Dot(a,u))<std::atan2(Dot(b,v),Dot(b,u));});
                for(int i=1;i+1<count;++i){
                    Vec3 a=cut[0],b=cut[i],c=cut[i+1];Vec3 face=Cross(b-a,c-a);
                    if(Length(face)<1e-7)continue;
                    if(Dot(face,Normal((a+b+c)*(1.0/3)))<0)std::swap(b,c);
                    int material=(Material(center)==0&&normal.z>.35)?0:1;
                    out.push_back({{{{a,Normal(a)},{b,Normal(b)},{c,Normal(c)}}},material});
                }
            }
        }
        return out;
    }
};
}
