clear all
clc


mm=zeros(3,18);
mt=zeros(3,18);

k=1;
for i=1:3
    if i==1
        eje='x';
        otro='z';
    elseif i==2
        eje='y';
        otro='x';
    else
        eje='z';
        otro='y';
    end
    for j=1:6
        if j==1
           theta='00';
        elseif j==2
            theta='30';
        elseif j==3;
            theta='45';
        elseif j==4
            theta='60';
        elseif j==5
            theta='90';
        else 
            theta='18';
        end        
            str=['./tests/mongoose/magnetometro/data_horizontal/' eje '00' otro theta ];
            [a,w,c,b,t]=mong_read(str,0);
            mm(:,k)=[mean(c(:,1)); mean(c(:,2));mean(c(:,3))];
            mt(:,k)=mag_teo(eje,'00',theta);  
            k=k+1;
    end
end



%% La majuga

x0=[2048/1.1 2048/1.1 2048/1.1 0 0 0 0 0 0 0 0 0];

[X,RESNORM,RESIDUAL,EXITFLAG]=lsqnonlin(@mag_cost,x0,[],[],optimset('MaxFunEvals',10000,'MaxIter',1000));

u=mean(RESIDUAL)
sigma=std(RESIDUAL)

save('mag','X','sigma')

%% Otra calibración
Q0=[1 0 0    0 1 0    0 0 1];
b0=[0 0 0];
x0=[Q0 b0];
[X,RESNORM,RESIDUAL,EXITFLAG]=lsqnonlin(@mag_cost2,x0,[],[],optimset('MaxFunEvals',10000,'MaxIter',1000));

Q=[X(1) X(2) X(3);
    X(4) X(5) X(6);
    X(7) X(8) X(9)];
b=[X(10); X(11); X(12)];


Hm=0.2306004;
[V,D]=eig(Q*Q');
u=-2*Q'*b;
k=b'*Q*b-Hm^2;
a=4*Hm^2/(4*k-(V'*u)'*D^(-1)*(V'*u));

save('mag','V','D','b','a')

%% La posta?

U = [0.00473160006403247     -2.18916898319836e-05      0.000309423482503981;
                         0       0.00455025410014059      7.83170752308679e-05;
                         0                         0       0.00534686558080686];
                     
c=  [23.3152609806586;
    -126.624459617958;
    19.0429011162953];


for i=1:length(mm(1,:));
mc(:,i)=(U*(mm(:,i)-c));
end



angulos=zeros(18,1);

for i=1:6
    angulos(i)=180/pi*atan2(mc(2,i),mc(3,i))+10;
end

for i=7:12
    angulos(i)=180/pi*atan2(-mc(3,i),-mc(1,i))+10;
end

for i=13:18
    angulos(i)=180/pi*atan2(-mc(1,i),mc(2,i))+10;
end

x1=6039;
y1=5625;
x2=2118;
y2=6415;
giro=180/pi*atan((y2-y1)/(x2-x1));

orientacion=[giro;giro+30;giro+45;giro+60;giro+90;giro+180];

error=[orientacion;orientacion;orientacion]-angulos