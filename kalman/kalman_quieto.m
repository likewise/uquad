% -------------------------------------------------------------------------
% Modelo fisico
% -------------------------------------------------------------------------
% d(z)/dt     = vqz*cos(psi)*cos(psi)
% d(psi)/dt   = wqx+wqz*tan(fi)*cos(psi)+wqy*tan(fi)*sin(psi);
% d(phi)/dt   = wqy*cos(psi)-wqz*sin(psi);
% d(theta)/dt = wqz*cos(psi)/cos(fi)+wqy*sin(psi)/cos(fi);
% d(vqz)/dt   = -g*cos(phi)*cos(psi)+1/M*(TM(1)+TM(2)+TM(3)+TM(4)) -> se asume vqx y vqy nulos
% d(wqx)/dt   = ( wqy*wqz*(Iyy-Izz)+wqy*Izzm*(w1-w2+w3-w4)+L*(T2-T4) )/Ixx;
% d(wqy)/dt   = ( wqx*wqz*(Izz-Ixx)+wqx*Izzm*(w1-w2+w3-w4)+L*(T3-T1) )/Iyy;
% d(wqz)/dt   = ( -Izzm*(dw1-dw2+dw3-dw4)+Q1-Q2+Q3-Q4 )/Izz;
% 
% -------------------------------------------------------------------------
% Estado
% -------------------------------------------------------------------------
% x = [z psi phi tehta vqz wqx wqy wqz]
% 
% -------------------------------------------------------------------------
% Kalman
% -------------------------------------------------------------------------
% A partir de los datos del gyro se hace un Kalman para la estimación de la
% velocidad angular en las 3 direcciones. A partir de los datos del
% magnetometro, convertidos a angulos de euler en mong_conv se estiman los
% angulos con el mismo filtro de kalman.
% A su vez con los datos de los acelerometros y los otros estados estimados
% se hallan las velocidades referenciadas al quad (vq) y por ultimo se
% incluye la estimacion de la posicion absoluta del quad, utilizando
% unicamente el modelo fisico. No se realiza correcion con ningun sensor a
% los estados x, y, z (posicion absoluta)
% -------------------------------------------------------------------------

% close all
clear all
clc

%% Observaciones y constantes

[acrud,wcrud,mcrud,tcrud,bcrud,~,~,T]=mong_read('log-zparriba4',0);
% [acrud,wcrud,mcrud,tcrud,bcrud,~,~,T]=mong_read('imu_raw_7.log',0,1);
[a,w,euler] = mong_conv(acrud,wcrud,mcrud,0);

b=altitud(bcrud);

% Test contra c - Descomentar esto para ver como se porta con datos
% promediados por la imu como entradas.
% %T = ones(size(T))*13000/1e6;% Debug, T cte
% xhat = load('./src/build/test/kalman_test/imu_data.log');
% a = xhat(:,4:6);
% w = xhat(:,7:9);
% euler = xhat(:,10:12);
% b = xhat(:,end);
% T = xhat(:,3)/1e6;

N  = size(a,1);         % Cantidad de muestras de las observaciones
Ns = 8;                % N states: cantidad de variables de estado
z  = [euler a(:,3) w b];     % Observaciones

%% Constantes

Ixx  = 2.32e-2;         % Tensor de inercia del quad - según x
Iyy  = 2.32e-2;         % Tensor de inercia del quad - según y
Izz  = 4.37e-2;         % Tensor de inercia del quad - según z
Izzm = 1.54e-5;         % Tensor de inercia de los motores - segun z
L    = 0.29;            % Largo en metros del los brazos del quad
M    = 1.541;           % Masa del Quad en kg
g    = 9.81;            % Aceleracion gravitatoria

%% Entradas

w  = 334.28*ones(N,4);              % Velocidades angulares de los motores en rad/s. Cada columna corresponde con 1 motor
dw = zeros(N,4);                    % Derivada de w. Cada columna corresponde a 1 motor
TM = 3.5296e-5*w.^2-4.9293e-4.*w;   % Fuerzas ejercidas por los motores en N. Cada columna corresponde a 1 motor.
D  = 3.4734e-6*w.^2-1.3205e-4.*w;   % Torque de Drag ejercido por los motores en N*m. Cada columna corresponde a cada motor

%% Kalman
     
f = @(z,psi,phi,theta,vqz,wqx,wqy,wqz,w,dw,TM,D,T) [ ...    
    z     + T*(vqz*cos(psi)*cos(psi));
    psi   + T*( wqx+wqz*tan(phi)*cos(psi)+wqy*tan(phi)*sin(psi));
    phi   + T*( wqy*cos(psi)-wqz*sin(psi));
    theta + T*( wqz*cos(psi)/cos(phi)+wqy*sin(psi)/cos(phi));
    vqz   + T*( -g*cos(phi)*cos(psi)+1/M*(TM(1)+TM(2)+TM(3)+TM(4)));
    wqx   + T*( wqy*wqz*(Iyy-Izz)+wqy*Izzm*(w(1)-w(2)+w(3)-w(4))+L*(TM(2)-TM(4)) )/Ixx ;
    wqy   + T*( wqx*wqz*(Izz-Ixx)+wqx*Izzm*(w(1)-w(2)+w(3)-w(4))+L*(TM(3)-TM(1)) )/Iyy;
    wqz   + T*( -Izzm*(dw(1)-dw(2)+dw(3)-dw(4))+D(1)-D(2)+D(3)-D(4) )/Izz ...
    ];

h = @(z,psi,phi,theta,wqx,wqy,wqz,TM) [ ... 
    psi ; 
    phi ; 
    theta ; 
    1/M*(TM(1)+TM(2)+TM(3)+TM(4)) ;
    wqx ; 
    wqy ; 
    wqz ;
    z ...
    ];

F = @(psi,phi,theta,vqz,wqx,wqy,wqz,w,T) ... 
    [...
    1,                            -2*T*vqz*cos(psi)*sin(psi),                                                                           0, 0, T*cos(psi)^2,                                                       0,                                                      0,                        0;
    0, T*(wqy*cos(psi)*tan(phi) - wqz*sin(psi)*tan(phi)) + 1,           T*(wqz*cos(psi)*(tan(phi)^2 + 1) + wqy*sin(psi)*(tan(phi)^2 + 1)), 0,            0,                                                       T,                                    T*sin(psi)*tan(phi),      T*cos(psi)*tan(phi);
    0,                      -T*(wqz*cos(psi) + wqy*sin(psi)),                                                                           1, 0,            0,                                                       0,                                             T*cos(psi),              -T*sin(psi);
    0, T*((wqy*cos(psi))/cos(phi) - (wqz*sin(psi))/cos(phi)), T*((wqz*cos(psi)*sin(phi))/cos(phi)^2 + (wqy*sin(phi)*sin(psi))/cos(phi)^2), 1,            0,                                                       0,                                  (T*sin(psi))/cos(phi),    (T*cos(psi))/cos(phi);
    0,                                 T*g*cos(phi)*sin(psi),                                                       T*g*cos(psi)*sin(phi), 0,            1,                                                       0,                                                      0,                        0;
    0,                                                     0,                                                                           0, 0,            0,                                                       1, (T*(wqz*(Iyy - Izz) + Izzm*(w(1)-w(2)+w(3)-w(4))))/Ixx,  (T*wqy*(Iyy - Izz))/Ixx;
    0,                                                     0,                                                                           0, 0,            0, -(T*(wqz*(Ixx - Izz) - Izzm*(w(1)-w(2)+w(3)-w(4))))/Iyy,                                                      1, -(T*wqx*(Ixx - Izz))/Iyy;
    0,                                                     0,                                                                           0, 0,            0,                                                       0,                                                      0,                        1 ...
    ]; 

H = @() ...
    [...
    0, 1, 0, 0, 0, 0, 0, 0;
    0, 0, 1, 0, 0, 0, 0, 0;
    0, 0, 0, 1, 0, 0, 0, 0;
    0, 0, 0, 0, 0, 0, 0, 0;
    0, 0, 0, 0, 0, 1, 0, 0;
    0, 0, 0, 0, 0, 0, 1, 0;
    0, 0, 0, 0, 0, 0, 0, 1;
    1, 0, 0, 0, 0, 0, 0, 0 ...
    ];

% Q = sigma_w^2*eye(Ns);  % 10*eye(Ns)
% Q = 100*eye(Ns);
Q = diag(.1*[100 100 100 100 10 10 10 100]);
R = diag(10000*[100 100 100 10 100 100 100 10]);
% z  = [euler a(:,3) w b]
P = 1*eye(Ns);
x_hat=zeros(N,Ns);

% psi_init   = z(1,1);
% phi_init   = z(1,2);
% theta_init = z(1,3);
% wqx_init   = z(1,7);
% wqy_init   = z(1,8);
% wqz_init   = z(1,9);
% vqx_init   = 0;%-(TM(1,1)*wqx_init + TM(1,2)*wqx_init + TM(1,3)*wqx_init + TM(1,4)*wqx_init - M*z(1,4)*wqx_init - M*z(1,5)*wqy_init - M*z(1,6)*wqx_init + M*g*wqx_init*sin(phi_init) - M*g*wqx_init*cos(phi_init)*cos(psi_init) - M*g*wqy_init*cos(phi_init)*sin(psi_init))/(M*wqy_init*(wqx_init - wqz_init));
% vqy_init   = 0;%-(TM(1,1)*wqz_init + TM(1,2)*wqz_init + TM(1,3)*wqz_init + TM(1,4)*wqz_init - M*z(1,4)*wqx_init - M*z(1,5)*wqy_init - M*z(1,6)*wqz_init + M*g*wqx_init*sin(phi_init) - M*g*wqz_init*cos(phi_init)*cos(psi_init) - M*g*wqy_init*cos(phi_init)*sin(psi_init))/(M*wqz_init*(wqx_init - wqz_init));
% vqz_init   = 0;%-(TM(1,1)*wqz_init + TM(1,2)*wqz_init + TM(1,3)*wqz_init + TM(1,4)*wqz_init - M*z(1,4)*wqz_init - M*z(1,5)*wqy_init - M*z(1,6)*wqz_init + M*g*wqz_init*sin(phi_init) - M*g*wqz_init*cos(phi_init)*cos(psi_init) - M*g*wqy_init*cos(phi_init)*sin(psi_init))/(M*wqy_init*(wqx_init - wqz_init));
% xinit = T(1) *(vqx_init*cos(phi_init)*cos(theta_init)+vqy_init*(cos(theta_init)*sin(phi_init)*sin(psi_init)-cos(phi_init)*sin(theta_init))+vqz_init*(sin(psi_init)*sin(theta_init)+cos(psi_init)*cos(theta_init)*sin(phi_init)) );
% yinit = T(1) *(vqx_init*cos(phi_init)*sin(theta_init)+vqy_init*(sin(theta_init)*sin(phi_init)*sin(psi_init)+cos(psi_init)*cos(theta_init))+vqz_init*(cos(psi_init)*sin(theta_init)*sin(phi_init)-cos(theta_init)*sin(psi_init)) );
% % zinit = T(1) *(-vqx_init*sin(phi_init)+vqy_init*cos(phi_init)*sin(psi_init)+vqz_init*cos(psi_init)*cos(psi_init));
% zinit = b(1);
% x_hat(1,:)=[ xinit yinit zinit psi_init phi_init theta_init vqx_init vqy_init vqz_init wqy_init wqx_init wqz_init];
% clear psi_init; clear phi_init; clear theta_init; clear wqx_init; clear wqy_init; clear wqz_init; clear vqx_init; clear vqy_init; clear vqz_init; clear xinit; clear yinit; clear zinit;

for i=2:N
    % Prediction
    x_   = f(x_hat(i-1,1),x_hat(i-1,2),x_hat(i-1,3),x_hat(i-1,4), ...
      x_hat(i-1,5),x_hat(i-1,6),x_hat(i-1,7),x_hat(i-1,8),w(i-1,:), ...
      dw(i-1,:), TM(i-1,:),D(i-1,:),T(i-1));

    Fk_1 = F(x_hat(i-1,2),x_hat(i-1,3),x_hat(i-1,4),x_hat(i-1,5), ...
      x_hat(i-1,6),x_hat(i-1,7),x_hat(i-1,8),w(i-1,:),T(i-1));

    P_   = Fk_1 * P * Fk_1'+ Q; 
    
    % Update
    yk         = z(i,:)' - h(x_(1),x_(2),x_(3),x_(4),x_(6),x_(7),x_(8), ...
      TM(i-1,:));
    Hk         = H();
    Sk         = Hk*P_*Hk' + R;
    Kk         = P_*Hk'*Sk^-1;
    x_hat(i,:) = x_ + Kk*yk;
    P          = (eye(Ns)-Kk*Hk)*P_;
end


% %% Plots

% figure()

subplot(221)
    plot(b,'k')
    hold on; grid
    plot([x_hat(1:end,1)],'b')
    legend('barom','z')
    hold off    

subplot(222)
    plot(z(:,1),'k')
    hold on; grid
    plot(z(:,2),'k')
    plot(z(:,3),'k')    
    plot([x_hat(1:end,2)],'b')
    plot([x_hat(1:end,3)],'r')
    plot([x_hat(1:end,4)],'g')
    legend('\psi','\phi','\theta','\psi','\phi','\theta')
    hold off    
    
subplot(223)
    plot([x_hat(1:end,5)],'b')
    legend('v_{qz}')
    hold off

subplot(224)
    plot(z(:,5),'k')
    hold on; grid
    plot(z(:,6),'k')
    plot(z(:,7),'k')    
    plot([x_hat(1:end,6)],'b')
    plot([x_hat(1:end,7)],'r')
    plot([x_hat(1:end,8)],'g')
    legend('w_x','w_y','w_z','w_x','w_y','w_z')
    hold off
    
% figure()
% subplot(211)
%     plot(z(:,1)-[x_hat(1:end,4)],'b')
%     hold on; grid
%     plot(z(:,2)-[x_hat(1:end,5)],'r')
%     plot(z(:,3)-[x_hat(1:end,6)],'g')    
%     legend('\psi','\phi','\theta')
%     title('Errores en angulos')
%     hold off
% subplot(212)
%     plot(z(:,7)-[x_hat(1:end,10)],'b')
%     hold on; grid
%     plot(z(:,8)-[x_hat(1:end,11)],'r')
%     plot(z(:,9)-[x_hat(1:end,12)],'g')    
%     legend('w_x','w_y','w_z')
%     title('Errores en velocidades angulares')
%     hold off